#!/bin/bash
# This is a mock version of a script with the same name that replaces all the real methods, which rely on external
# dependencies, such EC2 Metadata and AWS API calls, with mock versions that can run entirely locally. This allows us
# to test all the scripts completely locally using Docker.

set -e

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/strings.sh"

function get_instance_private_ip {
  hostname -i
}

function get_instance_public_ip {
  hostname -i
}

function get_instance_private_hostname {
  hostname -i
}

function get_instance_public_hostname {
  hostname -i
}

function get_instance_region {
  # This variable is set in docker-compose.yml
  echo "$mock_aws_region"
}

function get_ec2_instance_availability_zone {
  # This variable is set in docker-compose.yml
  echo "$mock_availability_zone"
}

# Return the container ID of the current Docker container. Per https://stackoverflow.com/a/25729598/2308858
function get_instance_id {
  cat /proc/1/cgroup | grep 'docker/' | tail -1 | sed 's/^.*\///'
}

# This mock returns a hard-coded, simplified version of the aws ec2 describe-tags call.
function get_instance_tags {
  local readonly instance_id="$1"
  local readonly instance_region="$2"

  # The cluster_asg_name below is an env var from docker-compose.yml
  cat << EOF
{
  "Tags": [
    {
      "ResourceType": "instance",
      "ResourceId": "$instance_id",
      "Value": "$cluster_asg_name",
      "Key": "Name"
    },
    {
      "ResourceType": "instance",
      "ResourceId": "$instance_id",
      "Value": "$cluster_asg_name",
      "Key": "aws:autoscaling:groupName"
    }
  ]
}
EOF
}

# This mock returns a hard-coded, simplified version of the aws autoscaling describe-auto-scaling-groups call.
function describe_asg {
  local readonly asg_name="$1"
  local readonly aws_region="$2"

  local readonly size=$(get_cluster_size "$asg_name" "$aws_region")

  cat << EOF
{
  "AutoScalingGroups": [
    {
      "AutoScalingGroupARN": "arn:aws:autoscaling:$aws_region:123456789012:autoScalingGroup:930d940e-891e-4781-a11a-7b0acd480f03:autoScalingGroupName/$asg_name",
      "DesiredCapacity": $size,
      "AutoScalingGroupName": "$asg_name",
      "LaunchConfigurationName": "$asg_name",
      "CreatedTime": "2013-08-19T20:53:25.584Z"
    }
  ]
}
EOF
}

# Get the size of the cluster. This comes from env vars set in docker-compose.yml. Note that if we are requesting the
# size of a cluster that isn't the one running in this Docker container, then we must instead be requesting the size of
# the replica cluster, so we return that.
function get_cluster_size {
  local readonly asg_name="$1"
  local readonly aws_region="$2"

  # All the variables are env vars set in docker-compose.yml
  if [[ "$asg_name" == "$cluster_asg_name" ]]; then
    echo -n "$cluster_size"
  else
    echo -n "$replica_cluster_size"
  fi
}

# Get the base name of the containers in the cluster. This comes from env vars set in docker-compose.yml. Note that if
# we are requesting the containers in a different cluster than the one this container is in, then we must instead be
# requesting looking for containers in the replica cluster, so we return that.
function get_container_basename {
  local readonly asg_name="$1"
  local readonly aws_region="$2"

  # All the variables are env vars set in docker-compose.yml
  if [[ "$asg_name" == "$cluster_asg_name" ]]; then
    echo -n "$data_node_container_base_name"
  else
    echo -n "$replica_data_node_container_base_name"
  fi

}

# This mock returns a hard-coded, simplified version of the aws ec2 describe-instances call.
function describe_instances_in_asg {
  local readonly asg_name="$1"
  local readonly aws_region="$2"

  local readonly size=$(get_cluster_size "$asg_name" "$aws_region")
  local readonly container_base_name=$(get_container_basename "$asg_name" "$aws_region")

  # cluster_size and data_node_container_base_name are env vars set in docker-compose.yml
  local instances_json=()
  for (( i=0; i<"$size"; i++ )); do
    instances_json+=("$(mock_instance_json "$asg_name" "$container_base_name-$i" "2018-03-17T17:38:3$i.000Z" "i-0ace993b1700c004$i")")
  done

  local readonly instances=$(join "," "${instances_json[@]}")

  cat << EOF
{
  "Reservations": [
    {
      "Instances": [
        $instances
      ]
    }
  ]
}
EOF
}

# Return the JSON for the "Instances" field of a aws ec2 describe-instances call
function mock_instance_json {
  local readonly asg_name="$1"
  local readonly container_name="$2"
  local readonly launch_time="$3"
  local readonly instance_id="$4"

  # These hostnames are set by Docker Compose networking using the names of the services
  # (https://docs.docker.com/compose/networking/). We use getent (https://unix.stackexchange.com/a/20793/215969) to get
  # the IP addresses for these hostnames, as that's what the servers themselves will advertise (see the mock
  # get_instance_xxx_hostname methods above).
  local readonly couchbase_hostname=$(getent hosts "$container_name" | awk '{ print $1 }')

  cat << EOF
{
  "LaunchTime": "$launch_time",
  "InstanceId": "$instance_id",
  "PublicIpAddress": "$couchbase_hostname",
  "PrivateIpAddress": "$couchbase_hostname",
  "PrivateDnsName": "$couchbase_hostname",
  "PublicDnsName": "$couchbase_hostname",
  "Tags": [
    {
      "Value": "$asg_name",
      "Key": "Name"
    },
    {
      "Value": "$asg_name",
      "Key": "aws:autoscaling:groupName"
    }
  ]
}
EOF
}