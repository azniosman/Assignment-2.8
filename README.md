# Assignment-2.8
Deployment as a Service

The script will now:
1. Check for existing VPC infrastructure
2. If no VPC is specified:
•  Try to use the default VPC
•  If no default VPC exists, create a new one with CIDR 10.0.0.0/16
3. Create/verify public subnets in two different availability zones
4. Create/verify Internet Gateway and attach it to the VPC
5. Create/verify public route table with Internet Gateway route
6. Associate public subnets with the route table

The VPC infrastructure will have:
•  Two public subnets (10.0.1.0/24 and 10.0.2.0/24) in different AZs
•  Internet Gateway for public internet access
•  Public route table with route to Internet Gateway
•  Auto-assign public IP enabled on public subnets

All resources will be properly tagged with "ElasticBeanstalk-" prefix for easy identification.

# Usage
./deploy.sh -a My-App -e MyEnv -r us-east-1 -p python.zip

./deploy.sh -a My-App -e MyEnv -r us-east-1 -p python.zip \
  --vpc-id vpc-093f15212228854f0 \
  --public-subnet-1 subnet-xxxxx \
  --public-subnet-2 subnet-yyyyy
