# To make scripts executable

chmod +x setup_static_site_deployment.sh

chmod +x teardown_static_site_deployment.sh

chmod +x post-merge


# Reference material

https://blog.puppy.vn/md/bash-script-create-and-validate-acm-certificate-aws

https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks

https://www.atlassian.com/git/tutorials/git-hooks

# Auxiliary tips

TIP: aws acm list-certificates --region us-east-1

TIP: to delete record, change action in `a-record-set.json` from "Action": "CREATE" -> "Action": "DELETE" ie: `delete-a-record-set-template.json`

TIP: https://docs.aws.amazon.com/general/latest/gr/s3.html - for getting hosted zone id of the s3 region

TIP: https://docs.aws.amazon.com/general/latest/gr/cf_region.html - for getting hosted zone if of the CloudFront