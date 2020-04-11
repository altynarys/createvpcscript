#!/bin/bash
echo "###################################################################"
echo "#--                       creating vpc in Ohio                  --#"
echo "###################################################################"
whereCreateVPC="us-east-2"
postFix="_Ohio_assign8"
NameTag="Name"
ohio="ohio"

#-------- vpc ID and NAME  -----------------#
vpcID="" 
vpcNameTagValue="vpc${postFix}"
cidrVPC="172.25.0.0/16"

#-------- rtb ID and NAME  -----------------#
rtbID=""
rtbNameTagValue="rtb${postFix}"

#-------- subnet ID and NAME  --------------#
subnetID=""
subnetNameTagValue="subnet${postFix}"
AZ_ID="use2-az1"
cidrSubnet="172.25.10.0/24"

#-------- igw ID and NAME ------------------#
igwID="" 
igwNameTagValue="igw${postFix}"

#-------- nacl ID and NAME -----------------#
naclID=""
naclNameTagValue="nacl${postFix}"

#-------- sg ID and NAME -------------------#
sgID=""
sgNameTagValue="sg${postFix}"

#-------- ec2 ID and NAME -------------------#
ec2ID=""
ec2NameTagValue="web_srv${postFix}"
ec2Type="t2.micro"
accountID=$(aws sts get-caller-identity --query "Account" --output text)
keyPair=$(aws ec2 describe-key-pairs | jq -r '.KeyPairs[0].KeyName')
imageID=$(aws ec2 describe-images --owner $accountID --query "Images[0].ImageId" --output text)

#-------- Current region -------------------#
aws configure set region $whereCreateVPC
curRegion=$(aws configure get profile.default.region)
echo -e "Current region: \033[1m$curRegion\033[0m"

#--- beginig of IF  ---#
if [ $curRegion != $whereCreateVPC ]
then
#--- then of IF  ---#
  echo -e "The region must be: \033[1m$whereCreateVPC\033[0m"
  echo "Creating VPC is interrupted"
else
#--- else of IF  ---#
  echo "Creating VPC..."

  #------- 1 creating and retrieving vpc ID  -------------------#
  vpcID=$(aws ec2 create-vpc \
        --cidr $cidrVPC \
        --instance-tenancy default \
        --no-amazon-provided-ipv6-cidr-block | jq -r '.Vpc.VpcId')
  aws ec2 modify-vpc-attribute --vpc-id $vpcID --enable-dns-hostnames
  
  #--------  assigning tag name to vpc -----------#
  aws ec2 create-tags --resources $vpcID --tags Key=$NameTag,Value=$vpcNameTagValue
  echo -e "\t--> VPC created, ID = \033[1m$vpcID\033[0m, Name = \033[1m$vpcNameTagValue\033[0m"

  #-------- 2 assigning tag name to route table --------#
  rtbID=$(aws ec2 describe-route-tables \
	--filter Name=vpc-id,Values=$vpcID > 2_get_rtb_ohio.json \
	&& \
	jq -r '.RouteTables[0].RouteTableId' 2_get_rtb_ohio.json)
  aws ec2 create-tags --resources $rtbID --tags Key=$NameTag,Value=$rtbNameTagValue
  echo -e "\t--> Route table created, ID = \033[1m$rtbID\033[0m, Name = \033[1m$rtbNameTagValue\033[0m"

  #--------- 3 creating and tagging subnet  ----------------#
  subnetID=$(aws ec2 create-subnet \
	--availability-zone-id $AZ_ID \
	--cidr-block $cidrSubnet \
	--vpc-id $vpcID > 3_create_subnet_ohio.json \
	&& \
	jq -r '.Subnet.SubnetId' 3_create_subnet_ohio.json)
  aws ec2 create-tags  --resources $subnetID --tags Key=$NameTag,Value=$subnetNameTagValue
  echo -e "\t--> Subnet created, ID = \033[1m$subnetID\033[0m, Name = \033[1m$subnetNameTagValue\033[0m"

  #--------- 4 creating, tagging internetGateway, and attaching to VPC  ------------#
   igwID=$(aws ec2 create-internet-gateway > 4_create_igw_ohio.json \
	&& \
	jq -r '.InternetGateway.InternetGatewayId' 4_create_igw_ohio.json)
   aws ec2 create-tags --resources $igwID --tags Key=$NameTag,Value=$igwNameTagValue
   aws ec2 attach-internet-gateway --internet-gateway-id $igwID --vpc-id $vpcID
   echo -e "\t--> InternetGateway created, ID =\033[1m$igwID\033[0m, Name = \033[1m$igwNameTagValue\033[0m and attached to VPC"

  #--------- 5 associating rtb, subnet and igw   ----------#
  aws ec2 create-route \
	--route-table-id $rtbID --destination-cidr-block 0.0.0.0/0 \
	--gateway-id $igwID > /dev/null
  aws ec2 associate-route-table --route-table-id $rtbID \
	--subnet-id $subnetID > 5_associate_rtb_subnet_igw_ohio.json
  echo -e "\t--> Associating \033[1m$rtbNameTagValue\033[0m, \033[1m$subnetNameTagValue\033[0m and \033[1m$igwNameTagValue\033[0m done"

  #--------- 6 nacl tagging   ----------#
  naclID=$(aws ec2 describe-network-acls --filters Name=vpc-id,Values=$vpcID > 6_nacl_ohio.json \
	 && \
	 jq -r '.NetworkAcls[0].NetworkAclId' 6_nacl_ohio.json)
  aws ec2 create-tags --resources $naclID --tags Key=$NameTag,Value=$naclNameTagValue
  echo -e "\t--> Network ACL, ID =\033[1m$naclID\033[0m, Name = \033[1m$naclNameTagValue\033[0m"

  #--------- 7 sg creating and tagging ------------#
  sgID=$(aws ec2 create-security-group \
	--description sg_EC2_SSH_HTTP_ALL$postFix \
	--group-name $sgNameTagValue \
	--vpc-id $vpcID | jq -r '.GroupId')
  aws ec2 create-tags --resources $sgID --tags Key=$NameTag,Value=$sgNameTagValue
  echo -e "\t--> Security group created, ID =\033[1m$sgID\033[0m, Name = \033[1m$sgNameTagValue\033[0m and attached to VPC:"
  aws ec2 authorize-security-group-ingress \
	--group-id $sgID --protocol tcp --port 22 --cidr 0.0.0.0/0 
  aws ec2 authorize-security-group-ingress \
	--group-id $sgID --protocol tcp --port 80 --cidr 0.0.0.0/0  
  echo -e "\t\tAllowed ingress:\n\t\t\tprotocols: \033[1mTCP\033[0m;\n\t\t\tports: \033[1m22, 80\033[0m;\n\t\t\tsources: \033[1m0.0.0.0/0\033[0m"
  aws ec2 describe-security-groups --filters Name=group-id,Values=$sgID > 7_sg_ohio.json
  aws ec2 describe-vpcs --vpc-ids $vpcID > 1_create_vpc_ohio.json
 
#--------- 8 ecc creating and tagging ------------#
  aws ec2 run-instances \
        --image-id $imageID \
        --count 1 \
        --subnet-id $subnetID \
        --instance-type $ec2Type \
        --associate-public-ip-address \
        --security-group-ids $sgID \
	--key-name $keyPair > 8_ec2_ohio.json

  ec2ID=$(jq -r '.Instances[0].InstanceId' 8_ec2_ohio.json)
  ec2State=""
  aws ec2 create-tags --resources $ec2ID --tags Key=$NameTag,Value=$ec2NameTagValue 
  echo -e "\t--> EC2 created, ID =\033[1m$ec2ID\033[0m, Name = \033[1m$ec2NameTagValue\033[0m"
  echo -e "\t--> Key pair applied, Name = \033[1m$keyPair\033[0m"
  while [ "$ec2State" != "running" ]
  do
     sleep 2s
     ec2State=$(aws ec2 describe-instance-status --instance-ids $ec2ID | jq -r '.InstanceStatuses[0].InstanceState.Name')
     echo -e "\t\t EC2 status: \033[1m$ec2State\033[0m"
  done
  dnsEC2=$(aws ec2 describe-instances --instance-ids $ec2ID | jq -r '.Reservations[0].Instances[0].PublicDnsName')
  echo -e "\t--> EC2 public DNS: \033[1m$dnsEC2\033[0m"
  echo "###################################################################"
  echo "#--             vpc in Ohio has been created                    --#"
  echo "###################################################################"
  aws configure set region us-east-1
 #--- end of IF  ---#
fi
