# TLDR - Walkthrough of aws-cli commands for your entertainment.

## CONFIG

S3_BUCKET=<S3_BUCKET_NAME>

export AWS_PROFILE=<YOUR_AWS_PROFILE_HERE> // for picking which creds to use

CLOUDFRONT_DESCRIPTION=<YOUR_CLOUDFRONT_DISTRO_DESCRIPTION_HERE>

AWS_REGION=<YOU_AWS_REGION>

S3_WEBSITE_URL="${S3_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"

S3_BUCKET_HOSTED_ZONE_ID=<YOUR_S3_BUCKET_HOSTED_ZONE_ID_HERE>

#### Check out ---> # https://docs.aws.amazon.com/general/latest/gr/s3.html

CLOUDFRONT_HOSTED_ZONE_ID=<YOUR_CLOUDFRONT_HOSTED_ZONE_ID_HERE>

#### Check out ---> # https://docs.aws.amazon.com/general/latest/gr/cf_region.html

IDEMPOTENCY_TOKEN=$(uuidgen | tr -d '\n-' | tr '[:upper:]' '[:lower:]' | cut -c1-6)

CLOUDFRONT_CALLER_REFERENCE_TOKEN=$(uuidgen | tr -d '\n-' | tr '[:upper:]' '[:lower:]' | cut -c1-8)

## STEP 1

### STEP 1a - Sanity Checks

$ aws --version
$ aws s3api help

## STEP 2

### STEP 2a - S3 commands

$ aws s3 mb s3://$S3_BUCKET
$ aws s3 rm s3://$S3_BUCKET --recursive
$ aws s3 sync ./build s3://$S3_BUCKET

### STEP 2b - Setup configuration json files

$ sed 's/S3_BUCKET/'"$S3_BUCKET"'/g' deployment-config/json/bucket-policy-template.json > deployment-config/json/bucket-policy.json

### STEP 2c - Setup Bucket for Hosting

$ aws s3api put-bucket-policy --bucket $S3_BUCKET --policy file://deployment-config/json/bucket-policy.json
$ aws s3 website s3://$S3_BUCKET --index-document index.html

#### STEP 2d Auxiliary

$ aws s3api put-public-access-block \
 --bucket $S3_BUCKET \
 --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
$ aws s3api put-public-access-block \
--bucket $S3_BUCKET \
--public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"

## STEP 3

TIP: aws acm list-certificates --region us-east-1

ACM_CERTIFICATE_ARN=$(aws acm request-certificate --domain-name $S3_BUCKET --validation-method DNS --idempotency-token $IDEMPOTENCY_TOKEN --region us-east-1 | jq '.CertificateArn')

## STEP 4

### STEP 4a

ACM_CERTIFICATE_ARN="$(echo $ACM_CERTIFICATE_ARN | sed -e 's#/#\\/#')"

$ sed -e 's/S3_BUCKET/'"$S3_BUCKET"'/g' -e 's/S3_WEBSITE_URL/'"$S3_WEBSITE_URL"'/g' -e 's/CLOUDFRONT_DESCRIPTION/'"$CLOUDFRONT_DESCRIPTION"'/g' -e 's/ACM_CERTIFICATE_ARN/'"$ACM_CERTIFICATE_ARN"'/g' -e 's/CLOUDFRONT_CALLER_REFERENCE_TOKEN/'"$CLOUDFRONT_CALLER_REFERENCE_TOKEN"'/g' deployment-config/json/dist-config-template.json > deployment-config/json/dist-config.json

### STEP 4b

aws cloudfront create-distribution --distribution-config file://deployment-config/json/dist-config.json

### STEP 4c - get the hosted zone id for the record

A_RECORD_NAME=${S3_BUCKET}.

CLOUDFRONT_A_RECORD_VALUE=$(aws cloudfront list-distributions | jq '.DistributionList.Items[] | select(.Aliases.Items[0] == '\"$S3_BUCKET\"')' | jq -r '.DomainName')

### STEP 4d - create records for Route53

$ sed -e 's/CLOUDFRONT_HOSTED_ZONE_ID/'"$CLOUDFRONT_HOSTED_ZONE_ID"'/g' -e 's/CLOUDFRONT_A_RECORD_VALUE/'"$CLOUDFRONT_A_RECORD_VALUE"'/g' -e 's/A_RECORD_NAME/'"$A_RECORD_NAME"'/g' deployment-config/json/a-record-set-template.json > deployment-config/json/a-record-set.json

TIP: To delete record, change action in `a-record-set.json` from "Action": "CREATE" -> "Action": "DELETE"

### STEP 4e

$ aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file://deployment-config/json/a-record-set.json --profile s3_user --region us-east-1

### STEP 4f - auxiliary tips

TIP: https://docs.aws.amazon.com/general/latest/gr/s3.html - for getting hosted zone id of the s3 region
TIP: https://docs.aws.amazon.com/general/latest/gr/cf_region.html - for getting hosted zone if of the CloudFront distribution

$ aws route53 list-resource-record-sets --hosted-zone-id Z098018037P2EA9EDT4PM
$ aws s3api get-bucket-website --bucket cmdsoftware.io

## STEP 5

### STEP 5a - Create CloudFront invalidation

CLOUDFRONT_DISTRO_ID==$(aws cloudfront list-distributions | jq '.DistributionList.Items[] | select(.Aliases.Items[0] == '\"$S3_BUCKET\"')' | jq -r '.Id')

aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_DISTRO_ID --paths "/\*"
