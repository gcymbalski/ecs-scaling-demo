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
          to_port 0
          cidr_ip '0.0.0.0/0'
          #cidr_ip ref!(:vpc_cidr)
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
                                            'ec2.amazonaws.com'
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
                           'ecs:CreateCluster',
                           'ecs:DeregisterContainerInstance',
                           'ecs:DiscoverPollEndpoint',
                           'ecs:Poll',
                           'ecs:RegisterContainerInstance',
                           'ecs:StartTelemetrySession',
                           'ecs:Submit*',
                           'ecr:GetAuthorizationToken',
                           'ecr:BatchCheckLayerAvailability',
                           'ecr:GetDownloadUrlForLayer',
                           'ecr:BatchGetImage',
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
                         'Resource' => ['*']
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

    subnets = registry!(:zones).collect{|zone| "public_#{zone.gsub('-','_')}_subnet"}
    # XXX eventually manage these container hosts with ASGs, if we really need to
    #dynamic!(:launch_configuration, 'ecs_instance', image_id: 'ami-022b9262', instance_type: 't2.medium', security_group: ref!(:ecs_security_group))
    #dynamic!(:auto_scaling_group, 'ecs_instance', launch_configuration_name: ref!('ecs_host_launch_configuration'), )

    ecs_host do
      type 'AWS::EC2::Instance'
      depends_on process_key!('nat_vpc_nat_route')
      properties do
        image_id 'ami-022b9262'
        instance_type 't2.medium'
    #   key_name 'testcluster'
        iam_instance_profile ref!(:ecs_instance_profile)
        security_group_ids [ref!(:ecs_security_group)]
        subnet_id ref!(subnets.first)
    #    network_interfaces([
    #        {
    #          'DeviceIndex' => 0,
    #          'AssociatePublicIpAddress' => 'true',
    #          'GroupSet' => [ref!(:ecs_security_group)],
    #          'DeleteOnTermination' => 'true',
    #          'SubnetId' => ref!(subnets.first)
    #        }
    #    ])
        user_data base64!(
          join!(
          "#!/bin/bash -v\n",
          "echo ECS_CLUSTER=ecs_cluster >> /etc/ecs/ecs.config\n"
          )
        )
      end
    end

  end

  outputs do
    ecs_cluster_name do
      value ref!(:ecs_cluster)
    end
    #ecs_host_ip_address do
    #  value attr!(:ecs_host, :public_ip)
    #end
    #ecs_host_dns_address do
    #  value attr!(:ecs_host, :public_dns_name)
    #end
  end
end
