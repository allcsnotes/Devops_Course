# Two tiny helpers used in Module 10. Load them with:  source helpers.sh
#
# tg <type> <name>  prints a tag specification with a Name tag and a Project tag
#   e.g. tg vpc allcsvideos-vpc
tg() {
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=allcsvideos}]"
}

# mk <name> <cidr> <az>  creates one subnet in $VPC and prints only its ID
#   e.g. PUBA=$(mk public-a 10.0.101.0/24 us-east-1a)
mk() {
  aws ec2 create-subnet --vpc-id "$VPC" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "$(tg subnet "$1")" --query Subnet.SubnetId --output text
}
