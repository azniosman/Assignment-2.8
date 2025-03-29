#!/bin/bash

# Enable automatic exit on error
# This will cause the script to exit immediately if any command exits with a non-zero status
set -e

# =============================
# Constants
# =============================
# Application and environment configuration
APP_NAME=""
ENV_NAME=""
VERSION_LABEL="v1.0.0-$(date +%Y%m%d-%H%M%S)"
REGION="us-east-1"

# VPC Configuration
VPC_ID=""
PUBLIC_SUBNET_1=""
PUBLIC_SUBNET_2=""

# AWS Elastic Beanstalk solution stack
SOLUTION_STACK="64bit Amazon Linux 2023 v4.5.0 running Python 3.11"

# IAM role names for Elastic Beanstalk
SERVICE_ROLE_NAME="aws-elasticbeanstalk-service-role"
INSTANCE_PROFILE_NAME="aws-elasticbeanstalk-ec2-role"

# The remaining sections will implement:
# - IAM Setup (Combined Roles)
# - Application Version Handling
# - Environment Creation with All Options
# - Validation & Waiters
# - Error Handling

# =============================
# Color Constants for Output Formatting
# =============================
# ANSI color codes for terminal output
RESET="\033[0m"          # Reset to default color
BLACK="\033[0;30m"       # Black
RED="\033[0;31m"         # Red
GREEN="\033[0;32m"       # Green
YELLOW="\033[0;33m"      # Yellow
BLUE="\033[0;34m"        # Blue
PURPLE="\033[0;35m"      # Purple
CYAN="\033[0;36m"        # Cyan
WHITE="\033[0;37m"       # White
BOLD="\033[1m"           # Bold text

# =============================
# Logging Functions
# =============================
# Print info message (green)
log_info() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

# Print warning message (yellow)
log_warn() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}

# Print error message (red)
log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

# Print success message (green bold)
log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $1"
}

# =============================
# IAM Setup Functions
# =============================
# Create service role if it doesn't exist
create_service_role() {
    log_info "Checking if service role '$SERVICE_ROLE_NAME' exists..."
    
    if aws iam get-role --role-name "$SERVICE_ROLE_NAME" &> /dev/null; then
        log_info "Service role '$SERVICE_ROLE_NAME' already exists."
    else
        log_info "Creating service role '$SERVICE_ROLE_NAME'..."
        
        # Create trust policy document for service role
        cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticbeanstalk.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        # Create the service role
        aws iam create-role \
            --role-name "$SERVICE_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/trust-policy.json
            
        # Attach managed policies to the service role
        log_info "Attaching managed policies to service role..."
        aws iam attach-role-policy \
            --role-name "$SERVICE_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
            
        aws iam attach-role-policy \
            --role-name "$SERVICE_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
            
        log_success "Successfully created service role '$SERVICE_ROLE_NAME'"
    fi
}

# Create instance profile if it doesn't exist
create_instance_profile() {
    log_info "Checking if instance profile '$INSTANCE_PROFILE_NAME' exists..."
    
    if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" &> /dev/null; then
        log_info "Instance profile '$INSTANCE_PROFILE_NAME' already exists."
    else
        log_info "Creating instance profile '$INSTANCE_PROFILE_NAME'..."
        
        # Create the instance profile
        aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"
        
        # Create trust policy document for EC2 role
        cat > /tmp/ec2-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        # Create the EC2 role
        log_info "Creating EC2 role for instance profile..."
        aws iam create-role \
            --role-name "$INSTANCE_PROFILE_NAME" \
            --assume-role-policy-document file:///tmp/ec2-trust-policy.json
            
        # Attach managed policies to the EC2 role
        log_info "Attaching managed policies to EC2 role..."
        aws iam attach-role-policy \
            --role-name "$INSTANCE_PROFILE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
            
        aws iam attach-role-policy \
            --role-name "$INSTANCE_PROFILE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
            
        aws iam attach-role-policy \
            --role-name "$INSTANCE_PROFILE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
        
        # Add the role to the instance profile
        log_info "Adding role to instance profile..."
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$INSTANCE_PROFILE_NAME" \
            --role-name "$INSTANCE_PROFILE_NAME"
            
        # Wait for the role to propagate
        log_info "Waiting for instance profile to be ready..."
        sleep 10
        
        log_success "Successfully created instance profile '$INSTANCE_PROFILE_NAME'"
    fi
}

# =============================
# VPC Infrastructure Setup
# =============================

# Setup VPC infrastructure (subnets, Internet Gateway, route table)
setup_vpc_infrastructure() {
    # Check if VPC_ID is provided
    if [ -z "$VPC_ID" ]; then
        log_info "No VPC ID provided. Attempting to use the default VPC..."
        # Get default VPC ID
        VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
        
        if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
            log_info "No default VPC found. Creating a new VPC..."
            # Create a new VPC with CIDR 10.0.0.0/16
            VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query "Vpc.VpcId" --output text)
            aws ec2 create-tags --resources "$VPC_ID" --tags "Key=Name,Value=ElasticBeanstalk-VPC"
            log_success "Created new VPC: $VPC_ID"
            
            # Enable DNS support and hostnames for the VPC
            aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
            aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
        else
            log_info "Using default VPC: $VPC_ID"
        fi
    fi
    
    # Get available availability zones
    AZS=($(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[?State=='available'].ZoneName" --output text))
    if [ ${#AZS[@]} -lt 2 ]; then
        log_error "Not enough availability zones in region $REGION"
        exit 1
    fi
    
    # Check if public subnets already exist
    if [ -n "$PUBLIC_SUBNET_1" ] && [ -n "$PUBLIC_SUBNET_2" ]; then
        log_info "Using provided public subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
    else
        log_info "Creating public subnets in VPC $VPC_ID..."
        
        # Create public subnet 1 in first AZ
        PUBLIC_SUBNET_1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "${AZS[0]}" --query "Subnet.SubnetId" --output text)
        aws ec2 create-tags --resources "$PUBLIC_SUBNET_1" --tags "Key=Name,Value=ElasticBeanstalk-Public1"
        # Enable auto-assign public IP
        aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_1" --map-public-ip-on-launch
        log_info "Created public subnet 1: $PUBLIC_SUBNET_1 in ${AZS[0]}"
        
        # Create public subnet 2 in second AZ
        PUBLIC_SUBNET_2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "${AZS[1]}" --query "Subnet.SubnetId" --output text)
        aws ec2 create-tags --resources "$PUBLIC_SUBNET_2" --tags "Key=Name,Value=ElasticBeanstalk-Public2"
        # Enable auto-assign public IP
        aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_2" --map-public-ip-on-launch
        log_info "Created public subnet 2: $PUBLIC_SUBNET_2 in ${AZS[1]}"
    fi
    
    # Create Internet Gateway if it doesn't exist
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[0].InternetGatewayId" --output text)
    
    if [ -z "$IGW_ID" ] || [ "$IGW_ID" = "None" ]; then
        log_info "Creating Internet Gateway for VPC $VPC_ID..."
        IGW_ID=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
        aws ec2 create-tags --resources "$IGW_ID" --tags "Key=Name,Value=ElasticBeanstalk-IGW"
        
        # Attach Internet Gateway to VPC
        aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
        log_success "Created and attached Internet Gateway: $IGW_ID"
    else
        log_info "Using existing Internet Gateway: $IGW_ID"
    fi
    
    # Create public route table with route to Internet Gateway
    # First check if a route table with IGW route already exists
    RT_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=route.gateway-id,Values=$IGW_ID" --query "RouteTables[0].RouteTableId" --output text)
    
    if [ -z "$RT_ID" ] || [ "$RT_ID" = "None" ]; then
        log_info "Creating public route table for VPC $VPC_ID..."
        RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query "RouteTable.RouteTableId" --output text)
        aws ec2 create-tags --resources "$RT_ID" --tags "Key=Name,Value=ElasticBeanstalk-Public-RT"
        
        # Add route to Internet Gateway
        aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
        log_success "Created public route table with IGW route: $RT_ID"
    else
        log_info "Using existing route table with IGW route: $RT_ID"
    fi
    
    # Associate public subnets with public route table
    log_info "Associating public subnets with route table $RT_ID..."
    aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$PUBLIC_SUBNET_1"
    aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$PUBLIC_SUBNET_2"
    
    log_success "VPC infrastructure setup complete"
    log_info "VPC: $VPC_ID"
    log_info "Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
    log_info "Internet Gateway: $IGW_ID"
    log_info "Public Route Table: $RT_ID"
}

# =============================
# Application Version Handling
# =============================
# Get AWS account ID for naming resources
get_aws_account_id() {
    aws sts get-caller-identity --query "Account" --output text
}

# Set the S3 bucket name based on region and account ID
ACCOUNT_ID=$(get_aws_account_id)
S3_BUCKET_NAME="elasticbeanstalk-${REGION}-${ACCOUNT_ID}"
DEPLOYMENT_PACKAGE="python.zip"  # Update this to match your deployment package name

# Validate the deployment package exists
validate_deployment_package() {
    log_info "Validating deployment package '$DEPLOYMENT_PACKAGE'..."
    
    if [ ! -f "$DEPLOYMENT_PACKAGE" ]; then
        log_error "Deployment package '$DEPLOYMENT_PACKAGE' not found!"
        log_error "Please make sure the deployment package exists in the current directory."
        exit 1
    fi
    
    if [ ! -s "$DEPLOYMENT_PACKAGE" ]; then
        log_error "Deployment package '$DEPLOYMENT_PACKAGE' is empty!"
        exit 1
    fi
    
    log_success "Deployment package validation successful."
}

# Create S3 bucket if it doesn't exist
create_s3_bucket() {
    log_info "Checking if S3 bucket '$S3_BUCKET_NAME' exists..."
    
    # Check if the bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log_info "S3 bucket '$S3_BUCKET_NAME' already exists."
    else
        log_info "Creating S3 bucket '$S3_BUCKET_NAME' in region '$REGION'..."
        
        # Create the bucket with region-specific command syntax
        if [ "$REGION" = "us-east-1" ]; then
            # us-east-1 doesn't use location constraint
            aws s3api create-bucket \
                --bucket "$S3_BUCKET_NAME" \
                --region "$REGION"
        else
            # All other regions need location constraint
            aws s3api create-bucket \
                --bucket "$S3_BUCKET_NAME" \
                --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION"
        fi
        
        # Enable versioning for the bucket
        aws s3api put-bucket-versioning \
            --bucket "$S3_BUCKET_NAME" \
            --versioning-configuration Status=Enabled
            
        log_success "Successfully created S3 bucket '$S3_BUCKET_NAME'"
    fi
}

# Upload artifact and create application version
create_application_version() {
    log_info "Creating application version '$VERSION_LABEL' for application '$APP_NAME'..."
    
    # First, check if application exists, and create if needed
    if ! aws elasticbeanstalk describe-applications --application-names "$APP_NAME" &>/dev/null; then
        log_info "Application '$APP_NAME' does not exist. Creating now..."
        aws elasticbeanstalk create-application --application-name "$APP_NAME" \
            --description "Application created by deployment script"
        log_success "Successfully created application '$APP_NAME'"
    fi
    
    # Upload the deployment package to S3
    log_info "Uploading deployment package to S3..."
    S3_KEY="${APP_NAME}/${VERSION_LABEL}.zip"
    
    if ! aws s3 cp "$DEPLOYMENT_PACKAGE" "s3://${S3_BUCKET_NAME}/${S3_KEY}"; then
        log_error "Failed to upload deployment package to S3!"
        exit 1
    fi
    
    log_info "Creating application version..."
    aws elasticbeanstalk create-application-version \
        --application-name "$APP_NAME" \
        --version-label "$VERSION_LABEL" \
        --description "Version $VERSION_LABEL deployed on $(date)" \
        --source-bundle S3Bucket="$S3_BUCKET_NAME",S3Key="$S3_KEY" \
        --auto-create-application
        
    log_success "Successfully created application version '$VERSION_LABEL'"
}

# =============================
# Environment Configuration and Creation
# =============================

# Default VPC configuration - update these values as per your AWS environment
VPC_ID=""                         # Your VPC ID
PUBLIC_SUBNET_1=""                # Public subnet 1
PUBLIC_SUBNET_2=""                # Public subnet 2
PRIVATE_SUBNET_1=""               # Private subnet 1
PRIVATE_SUBNET_2=""               # Private subnet 2
INSTANCE_TYPE="t3.small"          # EC2 instance type

# Create options.json with environment configurations
create_options_json() {
    local is_new_environment=$1
    
    log_info "Creating options.json with environment configurations..."
    
    # Define environment variables (customize as needed)
    ENV_VARS="{\\\"ENVIRONMENT\\\": \\\"production\\\", \\\"LOG_LEVEL\\\": \\\"info\\\"}"
    
    # Create options.json file
    cat > options.json << EOF
[
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "ServiceRole",
    "Value": "${SERVICE_ROLE_NAME}"
  },
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "IamInstanceProfile",
    "Value": "${INSTANCE_PROFILE_NAME}"
  },
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "InstanceType",
    "Value": "${INSTANCE_TYPE}"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "EnvironmentType",
    "Value": "LoadBalanced"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "LoadBalancerType",
    "Value": "application"
  },
  {
    "Namespace": "aws:elasticbeanstalk:application:environment",
    "OptionName": "ENVIRONMENT",
    "Value": "production"
  },
  {
    "Namespace": "aws:elasticbeanstalk:application:environment",
    "OptionName": "LOG_LEVEL",
    "Value": "info"
  }
EOF

    # Add VPC configuration only for new environments
    if [ -n "$VPC_ID" ] && [ "$is_new_environment" = "true" ]; then
        log_info "Adding VPC configuration to options.json for new environment..."
        cat >> options.json << EOF
,
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "VPCId",
    "Value": "$VPC_ID"
  },
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "Subnets",
    "Value": "$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2"
  },
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "ELBSubnets",
    "Value": "$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2"
  },
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "AssociatePublicIpAddress",
    "Value": "true"
  }
EOF
    fi

    # Close the JSON array
    echo "]" >> options.json
    
    log_success "Successfully created options.json"
}

# Check if environment exists
check_environment_exists() {
    log_info "Checking if environment '$ENV_NAME' exists..."
    
    if aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --query "Environments[?Status != 'Terminated'].Status" \
        --output text 2>/dev/null | grep -q "Ready\|Updating\|Launching"; then
        return 0  # Environment exists
    else
        return 1  # Environment doesn't exist
    fi
}

# Create or update Elastic Beanstalk environment
create_or_update_environment() {
    # Check if environment exists
    if check_environment_exists; then
        log_info "Environment '$ENV_NAME' already exists. Updating to version '$VERSION_LABEL'..."
        
        # Get current environment configuration for validation
        log_info "Retrieving current environment configuration..."
        local current_vpc_id=""
        current_vpc_id=$(aws elasticbeanstalk describe-configuration-settings \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --query "ConfigurationSettings[0].OptionSettings[?Namespace=='aws:ec2:vpc' && OptionName=='VPCId'].Value" \
            --output text)
        
        # If VPC ID is provided and different, warn that it can't be changed
        if [ -n "$VPC_ID" ] && [ -n "$current_vpc_id" ] && [ "$VPC_ID" != "$current_vpc_id" ]; then
            log_warn "Warning: VPC ID cannot be changed for existing environments"
            log_warn "Current VPC ID: $current_vpc_id, Requested VPC ID: $VPC_ID"
            log_warn "The existing VPC ID will be used and the requested VPC ID will be ignored"
        fi
        
        # Create options.json without VPC settings for existing environment
        create_options_json "false"
        
        # Update existing environment
        log_info "Updating existing environment without VPC settings..."
        aws elasticbeanstalk update-environment \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --option-settings file://options.json \
            --version-label "$VERSION_LABEL"
            
        wait_for_environment_update
    else
        log_info "Creating new environment '$ENV_NAME'..."
        
        # Create options.json with VPC settings for new environment
        create_options_json "true"
        
        # Create new environment
        aws elasticbeanstalk create-environment \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --option-settings file://options.json \
            --version-label "$VERSION_LABEL" \
            --solution-stack-name "$SOLUTION_STACK"
            
        wait_for_environment_update
    fi
}

# Wait for environment to finish updating
wait_for_environment_update() {
    log_info "Waiting for environment '$ENV_NAME' to reach Ready state..."
    
    local max_attempts=30
    local attempt=1
    local status=""
    
    while [ $attempt -le $max_attempts ]; do
        status=$(aws elasticbeanstalk describe-environments \
            --application-name "$APP_NAME" \
            --environment-names "$ENV_NAME" \
            --query "Environments[0].Status" \
            --output text)
            
        # Get health status too
        local health=""
        if [ "$status" == "Ready" ]; then
            health=$(aws elasticbeanstalk describe-environments \
                --application-name "$APP_NAME" \
                --environment-names "$ENV_NAME" \
                --query "Environments[0].Health" \
                --output text)
                
            log_info "Environment status: $status, Health: $health"
            
            if [ "$health" == "Green" ]; then
                log_success "Environment '$ENV_NAME' is ready and healthy!"
                return 0
            fi
        else
            log_info "Environment status: $status (attempt $attempt/$max_attempts)"
        fi
        
        # Check for failed state
        if [ "$status" == "Failed" ] || [ "$health" == "Red" ] && [ "$status" == "Ready" ]; then
            log_error "Environment deployment failed or is unhealthy!"
            aws elasticbeanstalk describe-events \
                --application-name "$APP_NAME" \
                --environment-name "$ENV_NAME" \
                --max-items 10
            exit 1
        fi
        
        sleep 20
        ((attempt++))
    done
    
    log_error "Timed out waiting for environment to become ready!"
    exit 1
}

# Get environment information
get_environment_info() {
    log_info "Getting information for environment '$ENV_NAME'..."
    
    local env_info
    env_info=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --query "Environments[0]" \
        --output json)
        
    if [ -z "$env_info" ] || [ "$env_info" == "null" ]; then
        log_error "Could not retrieve environment information!"
        return 1
    fi
    
    # Extract and display environment URL
    local env_url
    env_url=$(echo "$env_info" | grep -o '"EndpointURL": "[^"]*' | cut -d'"' -f4)
    
    if [ -n "$env_url" ]; then
        log_success "Environment URL: $env_url"
    else
        log_warn "Could not determine environment URL."
    fi
    
    return 0
}

# =============================
# Cleanup and Error Handling
# =============================

# Cleanup function to handle failures and cleanup resources
cleanup() {
    local exit_code=$1
    
    log_info "Performing cleanup operations..."
    
    # Remove temporary files
    if [ -f "/tmp/trust-policy.json" ]; then
        rm -f /tmp/trust-policy.json
    fi
    
    if [ -f "/tmp/ec2-trust-policy.json" ]; then
        rm -f /tmp/ec2-trust-policy.json
    fi
    
    if [ -f "options.json" ]; then
        # Keep the options.json file for debugging unless explicitly requested to clean
        if [ "$CLEAN_ALL" = "true" ]; then
            rm -f options.json
        fi
    fi
    
    log_info "Cleanup completed."
    
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        exit $exit_code
    fi
}

# =============================
# Script Usage Information
# =============================

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy an application to AWS Elastic Beanstalk.

Options:
  -a, --app-name NAME         Application name (default: $APP_NAME)
  -e, --env-name NAME         Environment name (default: $ENV_NAME)
  -v, --version-label LABEL   Version label (default: $VERSION_LABEL)
  -r, --region REGION         AWS region (default: $REGION)
  -p, --package FILE          Deployment package file (default: $DEPLOYMENT_PACKAGE)
  -t, --instance-type TYPE    EC2 instance type (default: $INSTANCE_TYPE)
  --vpc-id ID                 VPC ID for deployment
  --public-subnet-1 ID        Public subnet 1 ID
  --public-subnet-2 ID        Public subnet 2 ID
  --private-subnet-1 ID       Private subnet 1 ID
  --private-subnet-2 ID       Private subnet 2 ID
  --clean-all                 Remove all temporary files during cleanup
  -h, --help                  Show this help message

Examples:
  $(basename "$0") -a MyApp -e MyEnv -v v1.0.0 -r us-west-2 -p app.zip
  $(basename "$0") --vpc-id vpc-12345 --public-subnet-1 subnet-abc --public-subnet-2 subnet-def

EOF
}

# =============================
# Script Main Execution
# =============================

main() {
    log_info "Starting Elastic Beanstalk deployment script"
    
    # Parse command line arguments
    CLEAN_ALL="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--app-name)
                APP_NAME="$2"
                shift 2
                ;;
            -e|--env-name)
                ENV_NAME="$2"
                shift 2
                ;;
            -v|--version-label)
                VERSION_LABEL="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--package)
                DEPLOYMENT_PACKAGE="$2"
                shift 2
                ;;
            -t|--instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --vpc-id)
                VPC_ID="$2"
                shift 2
                ;;
            --public-subnet-1)
                PUBLIC_SUBNET_1="$2"
                shift 2
                ;;
            --public-subnet-2)
                PUBLIC_SUBNET_2="$2"
                shift 2
                ;;
            --private-subnet-1)
                PRIVATE_SUBNET_1="$2"
                shift 2
                ;;
            --private-subnet-2)
                PRIVATE_SUBNET_2="$2"
                shift 2
                ;;
            --clean-all)
                CLEAN_ALL="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$APP_NAME" ] || [ -z "$ENV_NAME" ]; then
        log_error "Application name (-a) and environment name (-e) are required!"
        show_usage
        exit 1
    fi
    
    # Print deployment parameters
    log_info "Deploying with the following parameters:"
    log_info "  Application Name: $APP_NAME"
    log_info "  Environment Name: $ENV_NAME"
    log_info "  Version Label: $VERSION_LABEL"
    log_info "  AWS Region: $REGION"
    log_info "  Deployment Package: $DEPLOYMENT_PACKAGE"
    log_info "  Instance Type: $INSTANCE_TYPE"
    
    if [ -n "$VPC_ID" ]; then
        log_info "  VPC Configuration: $VPC_ID"
        log_info "  Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
        log_info "  Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
    else
        log_info "  Network: Default VPC"
    fi
    
    # Step 1: Validate deployment package
    validate_deployment_package
    
    # Step 2: Create IAM roles if they don't exist
    create_service_role
    create_instance_profile
    
    # Step 3: Prepare S3 bucket and application version
    create_s3_bucket
    create_application_version
    
    # Step 4: Setup VPC infrastructure if needed
    setup_vpc_infrastructure
    
    # Step 5: Create or update environment
    create_options_json
    create_or_update_environment
    # Step 6: Display environment information
    get_environment_info
    
    log_success "Deployment completed successfully!"
    log_info "Your application '$APP_NAME' has been deployed to environment '$ENV_NAME'"
    
    # Clean up resources
    cleanup 0
}

# Set up trap to handle script interruption
trap 'log_error "Script interrupted. Cleaning up..."; cleanup 1' INT TERM EXIT

# Execute main function if the script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

