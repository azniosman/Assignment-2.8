#!/bin/bash

aws elasticbeanstalk create-environment \
  --application-name "Azni-App" \
  --environment-name "Azni-Env" \
  --solution-stack-name "64bit Amazon Linux 2023 v4.4.1 running Python 3.9" \
  --option-settings '[
    {
      "Namespace": "aws:ec2:vpc",
      "OptionName": "VPCId",
      "Value": "vpc-0aeae30a2b359b8f3"
    },
    {
      "Namespace": "aws:ec2:vpc",
      "OptionName": "Subnets",
      "Value": "subnet-0b64b42cb7c4e94e5,subnet-05630ee125c269724"
    },
    {
      "Namespace": "aws:ec2:vpc",
      "OptionName": "ELBSubnets",
      "Value": "subnet-0b64b42cb7c4e94e5,subnet-05630ee125c269724"
    },
    {
      "Namespace": "aws:ec2:vpc",
      "OptionName": "DBSubnets",
      "Value": "subnet-0de4e40b804b524bb,subnet-01114523a18ebe94d"
    },
    {
      "Namespace": "aws:ec2:vpc",
      "OptionName": "AssociatePublicIpAddress",
      "Value": "true"
    },
    {
      "Namespace": "aws:elasticbeanstalk:environment",
      "OptionName": "ServiceRole",
      "Value": "aws-elasticbeanstalk-service-role"
    },
    {
      "Namespace": "aws:autoscaling:launchconfiguration",
      "OptionName": "InstanceType",
      "Value": "t2.micro"
    },
    {
      "Namespace": "aws:autoscaling:launchconfiguration",
      "OptionName": "IamInstanceProfile",
      "Value": "aws-elasticbeanstalk-ec2-role"
    }
  ]'
