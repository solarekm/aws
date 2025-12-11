#!/usr/bin/env python3
"""
ECR Repository Scanner
Lists all ECR repositories and checks if 'scan on push' is enabled.
"""

import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from tabulate import tabulate
import sys


def get_ecr_repositories_with_scan_status(profile_name=None):
    """
    Fetch all ECR repositories and their scan on push status.
    
    Args:
        profile_name: AWS profile name to use (optional)
    
    Returns:
        List of dictionaries containing repository info
    """
    try:
        # Create ECR client
        session = boto3.Session(profile_name=profile_name) if profile_name else boto3.Session()
        ecr_client = session.client('ecr')
        
        repositories = []
        paginator = ecr_client.get_paginator('describe_repositories')
        
        # Iterate through all repositories
        for page in paginator.paginate():
            for repo in page['repositories']:
                repo_info = {
                    'Repository Name': repo['repositoryName'],
                    'Scan on Push': '✓ Enabled' if repo.get('imageScanningConfiguration', {}).get('scanOnPush', False) else '✗ Disabled',
                    'URI': repo['repositoryUri'],
                    'Created': repo['createdAt'].strftime('%Y-%m-%d %H:%M:%S')
                }
                repositories.append(repo_info)
        
        return repositories
    
    except NoCredentialsError:
        print("Error: AWS credentials not found. Please configure your credentials.", file=sys.stderr)
        sys.exit(1)
    except ClientError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    """Main function to display ECR repositories with scan status."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='List all ECR repositories and check if scan on push is enabled'
    )
    parser.add_argument(
        '--profile',
        help='AWS profile name to use',
        default=None
    )
    parser.add_argument(
        '--format',
        help='Output format (grid, simple, plain, pipe, html, latex)',
        default='grid',
        choices=['grid', 'simple', 'plain', 'pipe', 'html', 'latex', 'fancy_grid']
    )
    
    args = parser.parse_args()
    
    print(f"Fetching ECR repositories...")
    repositories = get_ecr_repositories_with_scan_status(args.profile)
    
    if not repositories:
        print("\nNo ECR repositories found.")
        return
    
    print(f"\nFound {len(repositories)} repository(ies):\n")
    
    # Display as table
    table_data = [
        [repo['Repository Name'], repo['Scan on Push'], repo['URI'], repo['Created']]
        for repo in repositories
    ]
    
    headers = ['Repository Name', 'Scan on Push', 'Repository URI', 'Created At']
    print(tabulate(table_data, headers=headers, tablefmt=args.format))
    
    # Summary
    enabled_count = sum(1 for repo in repositories if '✓' in repo['Scan on Push'])
    disabled_count = len(repositories) - enabled_count
    
    print(f"\n{'='*80}")
    print(f"Summary:")
    print(f"  Total repositories: {len(repositories)}")
    print(f"  Scan on push enabled: {enabled_count}")
    print(f"  Scan on push disabled: {disabled_count}")
    print(f"{'='*80}")


if __name__ == '__main__':
    main()
