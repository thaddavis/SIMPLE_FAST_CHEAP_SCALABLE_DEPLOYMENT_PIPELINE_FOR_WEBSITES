S3_BUCKET=<YOUR_BUCKET_NAME_HERE>
export AWS_PROFILE=<YOUR_AWS_IAM_PROFILE_HERE> # for picking which creds to use
CLOUDFRONT_DESCRIPTION=<DESCRIPTION_MESSAGE_FOR_CLOUDFRONT_DISTRO_HERE>
AWS_REGION=<YOUR_AWS_REGION_HERE>
S3_WEBSITE_URL="${S3_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
S3_BUCKET_HOSTED_ZONE_ID=<YOUR_S3_BUCKET_HOSTED_ZONE_ID_HERE> # Check out ---> # https://docs.aws.amazon.com/general/latest/gr/s3.html
CLOUDFRONT_HOSTED_ZONE_ID=<YOUR_CLOUDFRONT_HOSTED_ZONE_ID_HERE> # Check out ---> # https://docs.aws.amazon.com/general/latest/gr/cf_region.html
IDEMPOTENCY_TOKEN=$(uuidgen | tr -d '\n-' | tr '[:upper:]' '[:lower:]' | cut -c1-6)
CLOUDFRONT_CALLER_REFERENCE_TOKEN=$(uuidgen | tr -d '\n-' | tr '[:upper:]' '[:lower:]' | cut -c1-8)

aws --version
# STEP 1
aws s3 mb "s3://$S3_BUCKET" --region $AWS_REGION
# STEP 2
sed 's/S3_BUCKET/'"$S3_BUCKET"'/g' deployment-config/json/bucket-policy-template.json > deployment-config/json/bucket-policy.json
aws s3api put-bucket-policy --bucket $S3_BUCKET --policy file://deployment-config/json/bucket-policy.json
aws s3 website s3://$S3_BUCKET --index-document index.html
# STEP 3
ACM_CERTIFICATE_ARN=$(aws acm request-certificate --domain-name $S3_BUCKET --validation-method DNS --idempotency-token $IDEMPOTENCY_TOKEN --region $AWS_REGION --validation-method DNS | jq -r '.CertificateArn')
ACM_CERTIFICATE_ARN_ESCAPED="$(echo $ACM_CERTIFICATE_ARN | sed -e 's#/#\\/#')"
echo  "ACM_CERTIFICATE_ARN: $ACM_CERTIFICATE_ARN"
#
sleep 7 # waiting for ACM_CERTIFICATE to show up in the result of the following commands
#
VALIDATION_NAME="$(aws acm describe-certificate --certificate-arn "$ACM_CERTIFICATE_ARN" --region $AWS_REGION --query "Certificate.DomainValidationOptions[?DomainName=='$S3_BUCKET'].ResourceRecord.Name")"
echo "VALIDATION_NAME: $VALIDATION_NAME"
VALIDATION_VALUE="$(aws acm describe-certificate --certificate-arn "$ACM_CERTIFICATE_ARN" --region $AWS_REGION --query "Certificate.DomainValidationOptions[?DomainName=='$S3_BUCKET'].ResourceRecord.Value")"
echo "VALIDATION_VALUE: $VALIDATION_VALUE"
A_RECORD_NAME=${S3_BUCKET}.
R53_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones | jq '.HostedZones[] | select(.Name == '\"$A_RECORD_NAME\"') | .Id' | cut -d'"' -f 2 | cut -d'/' -f 3)
echo "R53_HOSTED_ZONE_ID: $R53_HOSTED_ZONE_ID"
#
R53_CHANGE_BATCH=$(cat <<EOM
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$VALIDATION_NAME",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$VALIDATION_VALUE"
          }
        ]
      }
    }
  ]
}
EOM
)
#
R53_CHANGE_BATCH_REQUEST_ID="$(aws route53 change-resource-record-sets \
--hosted-zone-id "$R53_HOSTED_ZONE" \
--region $AWS_REGION \
--change-batch "$R53_CHANGE_BATCH" \
--query "ChangeInfo.Id" \
--output text)"
#
echo "[Route 53]     Waiting for validation records to be created..."
aws route53 wait resource-record-sets-changed --id "$R53_CHANGE_BATCH_REQUEST_ID" --region $AWS_REGION
 #
echo "[ACM]          Waiting for certificate to validate..."
aws acm wait certificate-validated --certificate-arn "$ACM_CERTIFICATE_ARN" --region $AWS_REGION 

ACM_CERTIFICATE_STATUS="$(aws acm describe-certificate --region $AWS_REGION --certificate-arn "$ACM_CERTIFICATE_ARN" --query "Certificate.Status")"
ACM_CERTIFICATE="$(aws acm describe-certificate --region $AWS_REGION --certificate-arn "$ACM_CERTIFICATE_ARN")"

echo "ACM_CERTIFICATE_STATUS $ACM_CERTIFICATE_STATUS"
echo $ACM_CERTIFICATE_STATUS = "ISSUED"
echo "--- --- --- --- ---"

if [ $ACM_CERTIFICATE_STATUS = "\"ISSUED\"" ]; then
  echo "vvv ISSUED vvv"
  echo $ACM_CERTIFICATE | jq '.Certificate.CertificateArn'
  #
  sed -e 's/S3_BUCKET/'"$S3_BUCKET"'/g' -e 's/S3_WEBSITE_URL/'"$S3_WEBSITE_URL"'/g' -e 's/CLOUDFRONT_DESCRIPTION/'"$CLOUDFRONT_DESCRIPTION"'/g' -e 's/ACM_CERTIFICATE_ARN/'"$ACM_CERTIFICATE_ARN_ESCAPED"'/g' -e 's/CLOUDFRONT_CALLER_REFERENCE_TOKEN/'"$CLOUDFRONT_CALLER_REFERENCE_TOKEN"'/g' deployment-config/json/dist-config-template.json > deployment-config/json/dist-config.json
  # STEP 4
  CLOUDFRONT_DISTRO_ID=$(aws cloudfront create-distribution --distribution-config file://deployment-config/json/dist-config.json | jq -r '.Distribution.Id')
  echo "CLOUDFRONT_DISTRO_ID $CLOUDFRONT_DISTRO_ID"

  CLOUDFRONT_A_RECORD_VALUE=$(aws cloudfront list-distributions | jq '.DistributionList.Items[] | select(.Aliases.Items[0] == '\"$S3_BUCKET\"')' | jq -r '.DomainName')
  echo "CLOUDFRONT_A_RECORD_VALUE $CLOUDFRONT_A_RECORD_VALUE"

  # FINAL STEP 5
  sed -e 's/CLOUDFRONT_HOSTED_ZONE_ID/'"$CLOUDFRONT_HOSTED_ZONE_ID"'/g' -e 's/CLOUDFRONT_A_RECORD_VALUE/'"$CLOUDFRONT_A_RECORD_VALUE"'/g' -e 's/A_RECORD_NAME/'"$A_RECORD_NAME"'/g' deployment-config/json/a-record-set-template.json > deployment-config/json/a-record-set.json
  aws route53 change-resource-record-sets --hosted-zone-id $R53_HOSTED_ZONE_ID --change-batch file://deployment-config/json/a-record-set.json --region $AWS_REGION

  echo "...--- MADE IT TO THE END ---..."
else
  echo "vvv NOT ISSUED vvv"
  echo $ACM_CERTIFICATE | jq '.Certificate.CertificateArn'
fi