SparkleFormation.component(:ecs) do
  resources do
    backend_repo do
      type 'AWS::ECR::Repository'
      properties do
        repository_name 'backend'
      end
    end

    frontend_repo do
      type 'AWS::ECR::Repository'
      properties do
        repository_name 'frontend'
      end
    end

    ecs_cluster do
      type 'AWS::ECS::Cluster'
      properties do
        cluster_name 'ecs_cluster'
      end
    end

    ecs_security_group do
      type 'AWS::EC2::SecurityGroup'
      properties do
        vpc_id ref!(:vpc)
        group_description 'allow access to ecs cluster hosts on all tcp ports'
        security_group_ingress do
          ip_protocol 'tcp'
          from_port 0
          to_port 65_535
          # cidr_ip '0.0.0.0/0'
          cidr_ip ref!(:vpc_cidr)
        end
      end
    end

    ecs_iam_role do
      type 'AWS::IAM::Role'
      properties do
        assume_role_policy_document('Statement' => [
                                      {
                                        'Action' => [
                                          'sts:AssumeRole'
                                        ],
                                        'Effect'    => 'Allow',
                                        'Principal' => {
                                          'Service' => [
                                            'ec2.amazonaws.com',
				            'application-autoscaling.amazonaws.com',
			                    'ecs.amazonaws.com'
                                          ]
                                        }
                                      }
                                    ],
                                    'Version' => '2012-10-17')
        path '/'
        policies([
                   {
                     'PolicyName' => 'ecs_instance',
                     'PolicyDocument' => {
                       'Version' => '2012-10-17',
                       'Statement' => {
                         'Action' => [
        "application-autoscaling:*",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutMetricAlarm",
                           'ecs:CreateCluster',
                           'ecs:DeregisterContainerInstance',
                           'ecs:DiscoverPollEndpoint',
                           'ecs:Poll',
                           'ecs:RegisterContainerInstance',
                           'ecs:StartTelemetrySession',
                           'ecs:Submit*',
			   'ecs:UpdateService',
                           'ecs:DescribeServices',
                           'ecr:GetAuthorizationToken',
                           'ecr:GetDownloadUrlForLayer',
                           'ecr:BatchGetImage',
                           'ecr:BatchCheckLayerAvailability',
                           'ecr:PutImage',
                           'ecr:InitiateLayerUpload',
                           'ecr:UploadLayerPart',
                           'ecr:CompleteLayerUpload',
                           'logs:CreateLogStream',
                           'logs:PutLogEvents',
                           'ec2:AuthorizeSecurityGroupIngress',
                           'ec2:Describe*',
                           'elasticloadbalancing:DeregisterInstancesFromLoadBalancer',
                           'elasticloadbalancing:DeregisterTargets',
                           'elasticloadbalancing:Describe*',
                           'elasticloadbalancing:RegisterInstancesWithLoadBalancer',
                           'elasticloadbalancing:RegisterTargets'
                         ],
                         'Effect' => 'Allow',
                         'Resource' => '*'
                       }
                     }
                   }
                 ])
      end
    end

    ecs_instance_profile do
      type 'AWS::IAM::InstanceProfile'
      properties do
        path '/'
        roles [ref!(:ecs_iam_role)]
      end
    end

    subnets = registry!(:zones).collect { |zone| "private_#{zone.tr('-', '_')}_subnet" }
    ecs_host_launch_configuration do

 	     type 'AWS::AutoScaling::LaunchConfiguration'
             properties({image_id: 'ami-022b9262',
	     instance_type: 't2.large',
             iam_instance_profile: ref!(:ecs_instance_profile),
	     security_groups: [ref!(:ecs_security_group)],
        user_data: base64!(
          join!(
            "#!/bin/bash -v\n",
            "echo ECS_CLUSTER=",
            ref!(:ecs_cluster),
            " >> /etc/ecs/ecs.config\n"
          )
        )})

	    
    end

    ecs_host_auto_scaling_group do
	type 'AWS::AutoScaling::AutoScalingGroup'
	properties({
             launch_configuration_name: ref!('ecs_host_launch_configuration'),	
             'VPCZoneIdentifier': subnets.collect{|x| ref!(x)},
	     cooldown: '15',
	     desired_capacity: 2,
	     min_size: 1,
             max_size: 5})
    end
  end

  outputs do
    ecs_cluster do
      value ref!(:ecs_cluster)
    end
    ecs_iam_role do
      value ref!(:ecs_iam_role)
    end
    ecs_iam_role_arn do
	value attr!(:ecs_iam_role, :arn)
    end
    ecs_security_group do
      value ref!(:ecs_security_group)
    end
    ecs_instance_profile do
      value ref!(:ecs_instance_profile)
    end
  end
end
