CLUSTER_ID=k2mcbb6abg3l
CONTROLLER_GROUP=controller-hp01
INSTANCE_ID=i-09a31811762bf97be
TARGET_ID=sagemaker-cluster:${CLUSTER_ID}_${CONTROLLER_GROUP}-${INSTANCE_ID}
aws ssm start-session --target $TARGET_ID --profile ibm --region us-west-2
