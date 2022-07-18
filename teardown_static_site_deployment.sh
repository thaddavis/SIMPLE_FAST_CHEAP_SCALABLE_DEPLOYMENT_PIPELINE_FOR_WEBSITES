S3_BUCKET=<YOUR_BUCKET_NAME_HERE>
AWS_REGION=<YOUR_AWS_REGION_HERE>
A_RECORD_NAME=${S3_BUCKET}.
CLOUDFRONT_HOSTED_ZONE_ID=<YOUR_CLOUDFRONT_HOSTED_ZONE_ID_HERE> # Check out ---> # https://docs.aws.amazon.com/general/latest/gr/cf_region.html
export AWS_PROFILE=<YOUR_AWS_IAM_PROFILE_HERE> # for picking which creds to use

# --- --- --- --- DELETE BUCKET

# aws s3api delete-bucket --bucket $S3_BUCKET

# --- --- --- --- DELETE CERTIFICATE

# ACM_CERTIFICATE_ARN=$(aws acm list-certificates --region us-east-1 --profile s3_user | jq -r 'first(.CertificateSummaryList[] | select(.DomainName == '\"cmdlabs.io\"')).CertificateArn')
# ACM_CERTIFICATE_ARN=arn:aws:acm:us-east-1:333427308013:certificate/93d9c3af-d241-4525-b428-ab7eaa502f82
# aws acm delete-certificate --certificate-arn $ACM_CERTIFICATE_ARN --region $AWS_REGION --profile s3_user

# --- --- --- --- DELETE DISTRIBUTION

# CLOUDFRONT_DISTRO_ID=aws cloudfront list-distributions | jq -r '.DistributionList.Items[] | select(.Aliases.Items[0] == '\"$S3_BUCKET\"') | .Id'
# aws cloudfront delete-distribution --id $CLOUDFRONT_DISTRO_ID

# --- --- --- --- DELETE ROUTE53 RECORDS

# CLOUDFRONT_A_RECORD_VALUE=$(aws cloudfront list-distributions | jq '.DistributionList.Items[] | select(.Aliases.Items[0] == '\"$S3_BUCKET\"')' | jq -r '.DomainName')
# sed -e 's/CLOUDFRONT_HOSTED_ZONE_ID/'"$CLOUDFRONT_HOSTED_ZONE_ID"'/g' -e 's/CLOUDFRONT_A_RECORD_VALUE/'"$CLOUDFRONT_A_RECORD_VALUE"'/g' -e 's/A_RECORD_NAME/'"$A_RECORD_NAME"'/g' cicd/json/delete-a-record-set-template.json > cicd/json/delete-a-record-set.json
# HOSTED_ZONE_ID=$(aws route53 list-hosted-zones | jq '.HostedZones[] | select(.Name == '\"$A_RECORD_NAME\"') | .Id' | cut -d'"' -f 2 | cut -d'/' -f 3)
# aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file://cicd/json/delete-a-record-set.json --region $AWS_REGION