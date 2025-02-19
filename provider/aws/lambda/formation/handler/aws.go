package handler

import (
	"os"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/aws/aws-sdk-go/service/ecr"
	"github.com/aws/aws-sdk-go/service/ecs"
	"github.com/aws/aws-sdk-go/service/kms"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/sns"
	"github.com/aws/aws-sdk-go/service/sqs"
	"github.com/aws/aws-sdk-go/service/ssm"
)

func Credentials(req *Request) *credentials.Credentials {
	if req != nil {
		if access, ok := req.ResourceProperties["AccessId"].(string); ok && access != "" {
			if secret, ok := req.ResourceProperties["SecretAccessKey"].(string); ok && secret != "" {
				return credentials.NewStaticCredentials(access, secret, "")
			}
		}
	}

	if os.Getenv("AWS_ACCESS") != "" {
		return credentials.NewStaticCredentials(os.Getenv("AWS_ACCESS"), os.Getenv("AWS_SECRET"), "")
	}

	// return credentials.NewCredentials(&credentials.EC2RoleProvider{})
	return credentials.NewEnvCredentials()
}

func Region(req *Request) *string {
	if req != nil {
		if region, ok := req.ResourceProperties["Region"].(string); ok && region != "" {
			return aws.String(region)
		}
	}

	return aws.String(os.Getenv("AWS_REGION"))
}

func EC2(req Request) *ec2.EC2 {
	return ec2.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		Region:      Region(&req),
	})
}

func ECR(req Request) *ecr.ECR {
	return ecr.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		Region:      Region(&req),
	})
}

func ECS(req Request) *ecs.ECS {
	return ecs.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		MaxRetries:  aws.Int(8),
		Region:      Region(&req),
	})
}

func KMS(req Request) *kms.KMS {
	return kms.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		Region:      Region(&req),
		// There's a race condition when creating the key where sometimes the VPC KMS interface endpoint is not ready
		// so we increase the max retries here to make sure it won't fail
		// this is only used to create and delete a single KMS key for the rack so increasing the retries won't hurt
		MaxRetries: aws.Int(10),
	})
}

func S3(req Request) *s3.S3 {
	return s3.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		Region:      Region(&req),
	})
}

func SNS(req Request) *sns.SNS {
	return sns.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		Region:      Region(&req),
	})
}

func SQS() *sqs.SQS {
	return sqs.New(session.New(), &aws.Config{
		Credentials: Credentials(nil),
		Region:      Region(nil),
	})
}

func SSM(req Request) *ssm.SSM {
	return ssm.New(session.New(), &aws.Config{
		Credentials: Credentials(&req),
		Region:      Region(&req),
		MaxRetries:  aws.Int(10),
	})
}
