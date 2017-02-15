SparkleFormation.new(:ecs).overrides do
  
  parameters do
    ecs_cluster.type 'String'
    ecs_iam_role.type 'String'
    ecs_iam_role_arn.type 'String'
    ecs_security_group.type 'String'
    vpc_id.type 'String'
  end
  
  %w{public private}.each do |p|
    registry!(:zones).each do |z|
      parameters("#{p}_#{z.tr('-', '_')}_subnet") do
        type 'String'
      end
    end
  end

  ecrauth = ::Aws::ECR::Client.new.get_authorization_token
  unless ecrauth && ecrauth.authorization_data.first.proxy_endpoint
      puts "Unable to authenticate to ECR to negotiate images"
      exit -1
  end
  docker_endpoint = ecrauth.authorization_data.first.proxy_endpoint.slice(8..-1) # chop off https://
  
  %w{backend frontend}.each do |t|

    resources("#{t}_task_definition".to_sym) do
      type "AWS::ECS::TaskDefinition"
      depends_on process_key!("#{t}_alb")
      if t =~ /front/
        depends_on process_key!('backend_alb')
      end
      properties do
        container_definitions [
          {
            'Name': t,
            'Image': "#{docker_endpoint}/#{t}:0.5",
            'Memory': 128,
            'Cpu': 15,
            'Command': [ '/sbin/my_init' ],
            'Environment':  [
		{	'Name': 'BACKEND',
			'Value': attr!('backend_alb', 'DNSName')
		},
		{	'Name': 'BACKENDPORT',
			'Value': 80
		}
	     ],
            'PortMappings': [
                {
                  'ContainerPort': 80,
		  'HostPort': 0
                }
              ]
          }
        ]
        family t
      end
    end

    t_scheme = (t =~ /front/ ? 'internet-facing' : 'internal')
    t_subnet = (t =~ /front/ ? 'public' : 'private')
    
      resources("#{t}_alb") do
        type 'AWS::ElasticLoadBalancingV2::LoadBalancer'
        properties do
          scheme t_scheme
          subnets registry!(:zones).collect { |z| ref!("#{t_subnet}_#{z.tr('-', '_')}_subnet") }
          security_groups(t=~ /back/ ? [ ref!(:ecs_security_group) ] : [ ref!("#{t}_alb_sg") ])
        end
      end
  
      outputs("#{t}_alb_dns") do
        value attr!("#{t}_alb", 'DNSName')
      end

      resources("#{t}_alb_listener") do
	type 'AWS::ElasticLoadBalancingV2::Listener'
        depends_on process_key!("#{t}_alb")
        properties do
          default_actions [{'Type': 'forward', 'TargetGroupArn': ref!("#{t}_target_group")}]
          load_balancer_arn ref!("#{t}_alb")
          port '80'
          protocol 'HTTP'
        end
      end
      
      resources("#{t}_target_group") do
        type 'AWS::ElasticLoadBalancingV2::TargetGroup'
        depends_on process_key!("#{t}_alb")
        properties do
          health_check_interval_seconds 10
          health_check_path '/'
          health_check_protocol 'HTTP'
          health_check_timeout_seconds 5
          healthy_threshold_count 2
          port 80
          protocol 'HTTP'
          unhealthy_threshold_count 2
          vpc_id ref!(:vpc_id)
        end
      end

    if t =~ /front/
      resources("#{t}_scaling_target") do
        type 'AWS::ApplicationAutoScaling::ScalableTarget'
        depends_on process_key!("#{t}_service")
        properties({
          'RoleARN': ref!(:ecs_iam_role_arn),
	  max_capacity: 30,
	  min_capacity: 1,
          scalable_dimension: 'ecs:service:DesiredCount',
          service_namespace: 'ecs',
	  resource_id: join!('service/', ref!(:ecs_cluster), '/', attr!("#{t}_service", :name))
	})
      end

      resources("#{t}_scaling_up_policy") do
        type 'AWS::ApplicationAutoScaling::ScalingPolicy'
        properties do
	  policy_name "#{t}_scaling_up_policy"
          policy_type 'StepScaling'
          scaling_target_id ref!("#{t}_scaling_target".to_sym)
          step_scaling_policy_configuration do
            adjustment_type 'PercentChangeInCapacity'
            cooldown        10
            metric_aggregation_type 'Average'
            step_adjustments([{'MetricIntervalLowerBound':20, 'ScalingAdjustment': 250}])
          end
        end
      end
      
     resources("#{t}_scaling_down_policy") do
        type 'AWS::ApplicationAutoScaling::ScalingPolicy'
        properties do
	  policy_name "#{t}_scaling_down_policy"
          policy_type 'StepScaling'
          scaling_target_id ref!("#{t}_scaling_target".to_sym)
          step_scaling_policy_configuration do
            adjustment_type 'PercentChangeInCapacity'
            cooldown        30
            metric_aggregation_type 'Average'
            step_adjustments([{'MetricIntervalLowerBound':30, 'ScalingAdjustment': 200}])
          end
        end
      end
      
      resources("#{t}_alb_sg") do
        type 'AWS::EC2::SecurityGroup'
        properties do
          vpc_id ref!(:vpc_id)
          group_description 'allow access to ecs cluster hosts on all tcp ports'
          security_group_ingress do
            ip_protocol 'tcp'
            from_port 80
            to_port 80
            cidr_ip '0.0.0.0/0'
          end
        end
      end
    end

    resources("#{t}_service") do
      type 'AWS::ECS::Service'
      depends_on(process_key!('backend_service')) if t =~ /front/
      depends_on(process_key!("#{t}_alb_listener"))
      properties do
        cluster ref!(:ecs_cluster)
	deployment_configuration do
	  minimum_healthy_percent 50
	  maximum_percent(t =~ /back/ ? 100 : 150)
	end
        desired_count(t =~ /back/ ? 1 : 20)
        task_definition ref!("#{t}_task_definition")
        role ref!(:ecs_iam_role)
        load_balancers [{'ContainerName': t, 'ContainerPort': 80, 'TargetGroupArn': ref!("#{t}_target_group") }]
      end
    end
  end

end
