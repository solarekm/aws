# ECR Scan on Push Status Checker

Tools for checking the "Scan on Push" status of Amazon ECR repositories.

## Description

These scripts allow you to list all ECR repositories in an AWS account and verify whether the automatic image scanning on push (Scan on Push) option is enabled for each repository.

## Available Scripts

### 1. Python Script (`ecr-scan-status.py`)

Recommended option - more stable and easier to use.

#### Requirements
```bash
pip install boto3 tabulate
```

- **boto3** - AWS SDK for Python
- **tabulate** - library for formatting tables

#### Usage
```bash
# Basic usage (uses default AWS profile)
./ecr-scan-status.py

# With specific AWS profile
./ecr-scan-status.py --profile my-aws-profile

# Different output formats
./ecr-scan-status.py --profile my-aws-profile --format fancy_grid
./ecr-scan-status.py --profile my-aws-profile --format simple
./ecr-scan-status.py --profile my-aws-profile --format html
```

#### Parameters
- `--profile PROFILE` - AWS profile name to use
- `--format FORMAT` - table format (grid, simple, plain, pipe, html, latex, fancy_grid)

### 2. Bash Script (`ecr-scan-status.sh`)

Alternative option for Bash environments.

#### Requirements
```bash
# Debian/Ubuntu
sudo apt-get install jq

# RHEL/CentOS/Amazon Linux
sudo yum install jq

# macOS
brew install jq
```

- **aws-cli** - AWS Command Line Interface (usually already installed)
- **jq** - command-line JSON processor

#### Usage
```bash
# Basic usage (uses default AWS profile)
./ecr-scan-status.sh

# With specific AWS profile
./ecr-scan-status.sh --profile my-aws-profile

# Help
./ecr-scan-status.sh --help
```

#### Parameters
- `-p, --profile PROFILE` - AWS profile name to use
- `-h, --help` - display help message

## Example Output

```
Fetching ECR repositories...

Found 5 repository(ies):

Repository Name                          Scan on Push         Repository URI                                                                   Created At          
---------------------------------------- -------------------- -------------------------------------------------------------------------------- --------------------
my-api-service                          ✓ Enabled            123456789012.dkr.ecr.eu-central-1.amazonaws.com/my-api-service                  2024-01-15 10:30:22
legacy-app                              ✗ Disabled           123456789012.dkr.ecr.eu-central-1.amazonaws.com/legacy-app                      2023-11-20 14:22:11
frontend-app                            ✓ Enabled            123456789012.dkr.ecr.eu-central-1.amazonaws.com/frontend-app                    2024-03-10 09:15:33
backend-service                         ✓ Enabled            123456789012.dkr.ecr.eu-central-1.amazonaws.com/backend-service                 2024-02-28 16:45:00
test-repository                         ✗ Disabled           123456789012.dkr.ecr.eu-central-1.amazonaws.com/test-repository                 2024-04-05 11:20:15

====================================================================================
Summary:
  Total repositories: 5
  Scan on push enabled: 3
  Scan on push disabled: 2
====================================================================================
```

## AWS Permissions

The scripts require the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:DescribeRepositories"
      ],
      "Resource": "*"
    }
  ]
}
```

## AWS Configuration

Before using the scripts, ensure you have AWS credentials configured:

```bash
# For AWS SSO
aws sso login --profile your-profile

# Or check configuration
aws configure list
```

## Troubleshooting

### Error: "AWS credentials not found"
Configure AWS credentials or use the `--profile` parameter.

### Error: "jq: command not found" (Bash)
Install `jq` according to the instructions in the requirements section or use the Python script instead.

### Error: "No module named 'boto3'" (Python)
Install the required packages: `pip install boto3 tabulate`

## License

MIT
