#!/bin/bash

# Create the Elastic Beanstalk service role
aws iam create-role \
    --role-name aws-elasticbeanstalk-service-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "elasticbeanstalk.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }'

# Create the EC2 instance profile role
aws iam create-role \
    --role-name aws-elasticbeanstalk-ec2-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }'

# Attach policies to service role
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth

# Attach policies to EC2 role
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name aws-elasticbeanstalk-ec2-role

# Add role to instance profile
aws iam add-role-to-instance-profile \
    --instance-profile-name aws-elasticbeanstalk-ec2-role \
    --role-name aws-elasticbeanstalk-ec2-role

