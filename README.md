# Assignment-2.8
Deployment as a Service

# Basic usage
./deploy.sh

# With custom parameters
./deploy.sh -a MyApp -e MyEnv -v v1.0.0 -r us-west-2 -p app.zip

# With VPC configuration
./deploy.sh --vpc-id vpc-12345 --public-subnet-1 subnet-abc --public-subnet-2 subnet-def

./deploy.sh --help
