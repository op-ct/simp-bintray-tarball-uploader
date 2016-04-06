#!/usr/bin/env ruby

require 'rest_client'
require 'json'
require 'digest/sha1'
require 'highline/import'

def spacer
  puts "===================="
end

unless ARGV.size > 0
  fail "ERROR: Must supply SIMP tarball filenames"
end

STDOUT.flush
ARGV.each do |file|
  unless File.basename(file).match( /^SIMP-DVD-(?<flavor>[^-]+)-(?<xyz_ver>\d\.\d\.\d)-\d+\.tar\.gz$/ )['xyz_ver'] 
    fail "ERROR: Not a SIMP tarball filename: '#{file}'"
  end

  subject = 'simpdev'
  simp_flavor  = $~['flavor']
  simp_version = $~['xyz_ver'].sub(/\d+$/,'X')
  tarball_name = File.basename(file)
  tarball_sha1sum = %x(sha1sum #{file} | awk '{print $1}').chomp
  tarball_version = Time.now.strftime('%Y%m%d') 

  puts "file: '#{file}'"
  puts "simp_version: '#{simp_version}'"

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

  repo = "SIMP_#{simp_version}_nightly"

  begin
    RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/repos/#{subject}/#{repo}/")
  rescue => e
    unless e.response.code == 404
      fail "Error: #{e}"
    end

    repo_metadata = {
      'type' => 'generic',
      'private' => false,
      'premium' => false,
      'desc' => "This repository hosts #{simp_flavor} packages for SIMP #{simp_version}",
      'labels' => ['simp', 'simpdev'],
    }

    RestClient.post(
      "https://#{api_user}:#{api_key}@api.bintray.com/repos/#{subject}/#{repo}",
      JSON.generate(repo_metadata),
      {:content_type => :json}
    )
  end


    # Check to see if this thing is worth uploading

    repo_name = repo  # FIXME: replace 'repo' with 'repo' if it's safe
    puts("Processing #{file}")

    package_exists = false
    begin
      RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/packages/#{subject}/#{repo_name}/#{tarball_name}")
      package_exists = true
    rescue => e
      unless e.response.code == 404
        fail "Error: #{e}"
      end
    end

    unless package_exists
      spacer
      puts("Working on package: #{file}")
      spacer
      license = 'Apache-2.0'
      vcs_url = 'https://github.com/simp'
      labels = ['simp', 'simpdev', simp_flavor, simp_version, 'nightly', 'tarball']
      issue_tracker = 'https://simp-project.atlassian.net'

      package_data = {
        "name" => tarball_name,
        "desc" => "Nightly build package for #{simp_flavor} SIMP #{simp_version}",
        "labels" => labels,
        "licenses" => Array(license),
        "issue_tracker_url" => issue_tracker,
        "vcs_url" => vcs_url,
        "public_download_numbers" => true,
        "public_stats" => true
      }

      resp = RestClient.post(
        "https://#{api_user}:#{api_key}@api.bintray.com/packages/#{subject}/#{repo_name}",
        JSON.generate(package_data),
        {:content_type => :json}
      )
    end

    file_exists = false
    file_published = false
    begin
      files = RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/packages/#{subject}/#{repo_name}/#{tarball_name}/versions/#{tarball_version}/files?include_unpublished=1")
      files = JSON.parse(files)
      files.each do |file|
        if tarball_sha1sum == file['sha1']
          file_exists = true
        end
      end
    rescue => e
      unless e.response.code == 404
        fail "Error: #{e}"
      end
    end

    # Check if it's been published
    #  --------------------------------------------------------------------------
    if file_exists
      files = RestClient.get("https://#{api_user}:#{api_key}@api.bintray.com/packages/#{subject}/#{repo_name}/#{tarball_name}/versions/#{tarball_version}/files")
      files = JSON.parse(files)

      files.each do |file|
        if tarball_sha1sum == file['sha1']
          file_published = true
        end
      end
    end

    # Upload
    # --------------------------------------------------------------------------
    unless file_exists
      curl_cmd = %(curl -# -T #{file} ) +
        %(-u#{api_user}:#{api_key} ) +
        %(https://api.bintray.com/content/#{subject}/#{repo_name}/#{tarball_name}/#{tarball_version}/#{tarball_name})

      %x(#{curl_cmd})
      fail("Could not upload #{rpm}") unless $?.success?
    end

    # Publish
    # --------------------------------------------------------------------------
    unless file_published
      publish = true

      if publish
        publish_package = {
          "discard" => false,
          "publish_wait_for_secs" => 0
        }
        RestClient.post(
          "https://#{api_user}:#{api_key}@api.bintray.com/content/#{subject}/#{repo_name}/#{tarball_name}/#{tarball_version}/publish",
          JSON.generate(publish_package),
          {:content_type => :json}
        )
      end
    end

end

