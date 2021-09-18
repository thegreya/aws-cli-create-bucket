# aws-cli-create-bucket
A script which will create a private AWS S3 bucket with a set of IAM user credentials for access

### Prerequisites
To create the OneTimePassword link, run:
`sudo gem install onetime`

### Instructions
Run `sh aws-cli-create-bucket.sh`, and enter a your desired username as instructed.

The script will generate a private S3 bucket, an IAM User with access to the bucket, and an email text file with a working link to user credentials.
