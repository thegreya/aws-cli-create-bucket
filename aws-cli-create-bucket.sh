#!/bin/bash
set -eu
IFS=$'\n\t'

#Turn off CLI Pager
export AWS_PAGER=""

#Set Environment Variables
echo Enter  Username
read username

postfix="-bucket"
bucketname=$username$postfix

PS3="Select the bucket region: "

select opt in us-east-1 eu-west-1 quit; do
  case $opt in
    us-east-1)
      echo "Create Bucket in us-east-1"
      region="us-east-1"
      printf "# -------------------------------------------------------------------------\nProvisioning resources in for $username in $region\n# -------------------------------------------------------------------------\n\n"
      aws s3api create-bucket --bucket $bucketname --region $region --acl private
      break
      ;;
    eu-west-1)
      echo "Create Bucket in eu-west-1"
      region="eu-west-1"
      printf "# -------------------------------------------------------------------------\nProvisioning resources in for $username in $region\n# -------------------------------------------------------------------------\n\n"
      aws s3api create-bucket --bucket $bucketname --region $region --create-bucket-configuration LocationConstraint=eu-west-1 --acl private
      break
      ;;
    quit)
      break
      ;;
    *) 
      echo "Invalid option $REPLY"
      ;;
  esac
done


#Explicitly Block Public Access to Bucket
printf "Blocking Public Access to Bucket..."
aws s3api put-public-access-block \
    --bucket $bucketname \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
printf "Done \xe2\x9c\x85 \n"

#Create User Account
printf "Creating IAM User..."
aws iam create-user --user-name $username
printf "Done \xe2\x9c\x85 \n"

#Tag User Account
printf "Tagging IAM User..."
aws iam tag-user --user-name $username --tags Key=User,Value=$username  
printf "Done \xe2\x9c\x85 \n"

#Create Access Key for User, Immediately send secret key to variable
printf "Creating Access & Secret Key..."
secretkey=$(aws iam create-access-key --user-name $username --query '[AccessKey.SecretAccessKey]' --output text)
printf "Done \xe2\x9c\x85 \n"

#Get Access Key ID
accesskey=$(aws iam list-access-keys --user-name $username --query 'AccessKeyMetadata[0].AccessKeyId' --output text)

#Generate Bucket Access Policy JSON
printf "Generate Bucket Access Policy..."
policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::$bucketname"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$bucketname/*"
            ]
        }
    ]
}
EOF
)

#Generate Policy.json file
echo "$policy" > "policy.json"

#Attach In-line policy to User IAM account
aws iam put-user-policy --user-name $username --policy-name $username --policy-document file://policy.json 
printf "Done \xe2\x9c\x85 \n"

printf "Generate EC2 Trust Policy..."
#Trust Policy for EC2 to be able to create role
trust=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

#Generate role.json file
echo "$trust" > "trust.json"

#Create Temp EC2 Role in CDT account
aws iam create-role --role-name $bucketname --assume-role-policy-document file://trust.json
  
#Generate Bucket Access Policy JSON
role=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::$bucketname",
                "arn:aws:s3:::$bucketname/*"
            ]
        }
    ]
}
EOF
)

#Generate role.json file
echo "$role" > "role.json"

#Attach Temp EC2 Role Policy in CDT account
aws iam put-role-policy --role-name $bucketname --policy-name $bucketname --policy-document file://role.json
printf "Done \xe2\x9c\x85 \n"

#Add instance profile
printf "Create IAM Instance Profile..."
aws iam create-instance-profile --instance-profile-name $bucketname

aws iam add-role-to-instance-profile --role-name $bucketname --instance-profile-name $bucketname
printf "Done \xe2\x9c\x85 \n"

printf "Generate OneTimeSecret Link..."
#generate random password for onetime secret
randpass=$(LC_ALL=C tr -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' </dev/urandom | head -c 16)

#generate content for onetimepassword link
onetimecontent=$(cat <<EOF

S3 Bucket Name
$bucketname

Access Key
$accesskey

SecretKey
$secretkey

EOF
)

#credential prefix for filename
credprefix="credentials-"

#concat strings for filename
credfile=$credprefix$username

#Generate Credential file for reference
echo "$onetimecontent" > "$credfile.txt"

#generate onetime secret link with a random password and ttl of 1 week
onetimelink=$(echo $onetimecontent | onetime share -p $randpass -t 1209600)
printf "Done \xe2\x9c\x85 \n"

printf "Generate Email contents..."
#Generate Email Body to Copy/Paste to User
email=$(cat <<EOF

Hi $username,

Here is the link to the One Time Secret containing the AWS S3 access credentials.
Be sure to save the access info somewhere for future reference since this link will only work once.
$onetimelink

The password for the One Time Secret link is:
$randpass

The link will expire after you've viewed it once, or after 7 days, whichever comes first.

EOF
)

printf "Done \xe2\x9c\x85 \n"

printf "Credentials have been created and placed in a text file named $credfile for safe-keeping. \n"

printf "___________________________________________________________________________________________ \n"
printf "\n"

#Display Email
echo $email


#credential prefix for filename
emailbody="emailbody-"

#concat strings for filename
emailfile=$emailbody$username

#Generate email file for reference
echo "$email" > "$emailfile.txt"