A slight reworking of Trevor's old upload script to handle nightly build tarballs 

### Installing
```bash
bundle
```

### Setup
Create a file `.env` and populate it like so:
```
BINTRAY_API_USER=username
BINTRAY_API_KEY=apikey
```

### Usage
# To upload a nightly build for CentOS 5.1.X:
```bash
dotenv bundle exec ruby bintray_upload.rb /path/to/SIMP-DVD-CentOS-5.1.0-2.tar.gz  
```
