aws elasticbeanstalk create-application-version \
  --application-name "Azni-App" \
  --version-label "v1.0.0" \
  --source-bundle S3Bucket="azni",S3Key="python.zip"
