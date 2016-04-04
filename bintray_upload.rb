#!/usr/bin/env ruby

require 'rest_client'
require 'json'
require 'simp/rpm'
require 'digest/sha1'
require 'highline/import'

def spacer
  puts "===================="
end

simp_version = ask("SIMP Version? ")

if ENV['BINTRAY_API_USER']
  api_user= ENV['BINTRAY_API_USER']
else
  api_user= ''
  while api_user.empty?
    api_user= ask("BinTray API User? ")
  end
end

if ENV['BINTRAY_API_KEY']
  api_key = ENV['BINTRAY_API_KEY']
else
  api_key = ''
  while api_key.empty?
    api_key = ask("BinTray API Key? ")
  end
end


[simp_version, %(#{simp_version}-Source)].each do |repo|
  begin
    RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/repos/simp/#{repo}/")
  rescue => e
    unless e.response.code == 404
      fail "Error: #{e}"
    end

    # If we get here, the repo does not exist
    if repo == %(#{simp_version}-Source)
      repo_type = 'Source'
    else
      repo_type = 'Production'
    end

    repo_metadata = {
      'type' => 'rpm',
      'private' => false,
      'premium' => false,
      'desc' => "This repository hosts #{repo_type} packages for SIMP #{simp_version}",
      'labels' => ['simp']
    }

    RestClient.post(
      "https://#{api_user}:#{api_key}@api.bintray.com/repos/simp/#{repo}",
      JSON.generate(repo_metadata),
      {:content_type => :json}
    )
  end
end

Dir.glob("*.rpm").each do |rpm|
  # Check to see if this thing is worth uploading

  rpm_check = %x(rpm -K #{rpm})
  rpm_check = rpm_check.split(':')[1..-1]
  if rpm_check.grep(/pgp/i).empty?
    $stderr.puts("Warning: #{rpm} is not signed, SKIPPING")
    next
  end

  if rpm =~ /\.src\.rpm$/
    repo_name = "#{simp_version}-Source"
  else
    repo_name = simp_version
  end

  puts("Processing #{rpm}")

  rpm_info = Simp::RPM.get_info(rpm)
  puts('Generating Checksum (this may take some time)')
  rpm_checksum = Digest::SHA1.hexdigest(File.read(rpm))

  package_exists = false
  begin
    RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/packages/simp/#{repo_name}/#{rpm_info[:name]}")
    package_exists = true
  rescue => e
    unless e.response.code == 404
      fail "Error: #{e}"
    end
  end

  unless package_exists
    spacer
    puts("Working on package: #{rpm}")
    spacer
    license = ask("License? ") {|q| q.default = 'Apache-2.0'}
    vcs_url = ask("VCS URL? ") {|q| q.default = 'https://github.com/simp'}
    labels = ask("Labels? (comma sep) ", lambda {|str| str.split(/\s*,\s*/)})
    issue_tracker = ask("Issue Tracker? ") {|q| q.default = 'https://simp-project.atlassian.net'}

    package_data = {
      "name" => rpm_info[:name],
      "desc" => rpm_info[:summary],
      "labels" => labels,
      "licenses" => Array(license),
      "issue_tracker_url" => issue_tracker,
      "vcs_url" => vcs_url,
      "public_download_numbers" => true,
      "public_stats" => true
    }

    resp = RestClient.post(
      "https://#{api_user}:#{api_key}@api.bintray.com/packages/simp/#{repo_name}",
      JSON.generate(package_data),
      {:content_type => :json}
    )
  end

  file_exists = false
  file_published = false
  begin
    files = RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/packages/simp/#{repo_name}/#{rpm_info[:name]}/files?include_unpublished=1")
    files = JSON.parse(files)

    files.each do |file|
      if rpm_checksum == file['sha1']
        file_exists = true
      end
    end
  rescue => e
    unless e.response.code == 404
      fail "Error: #{e}"
    end
  end

  if file_exists
    files = RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/packages/simp/#{repo_name}/#{rpm_info[:name]}/files")
    files = JSON.parse(files)

    files.each do |file|
      if rpm_checksum == file['sha1']
        file_published = true
      end
    end
  end

  unless file_exists
    curl_cmd = %(curl -# -T #{rpm} ) +
      %(-u#{api_user}:#{api_key} ) +
      %(https://api.bintray.com/content/simp/#{repo_name}/#{rpm_info[:name]}/#{rpm_info[:version]}/#{rpm})

    %x(#{curl_cmd})
    fail("Could not upload #{rpm}") unless $?.success?
  end

  unless file_published
    publish = ask("Publish #{rpm}? ", lambda {|str| str =~ /(true|y(es)?)/i ? true : false}) {|q| q.default = false}

    if publish
      publish_package = {
        "discard" => false,
        "publish_wait_for_secs" => 0
      }
      RestClient.post(
        "https://#{api_user}:#{api_key}@api.bintray.com/content/simp/#{repo_name}/#{rpm_info[:name]}/#{rpm_info[:version]}/publish",
        JSON.generate(publish_package),
        {:content_type => :json}
      )
    end
  end
end

