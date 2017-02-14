SparkleFormation.new(:ecs).overrides do
  
  parameters do
    ecs_cluster.type 'String'
    ecs_iam_role.type 'String'
  end

  ecrauth = ::Aws::ECR::Client.new.get_authorization_token
  unless ecrauth && ecrauth.authorization_data.first.proxy_endpoint
      puts "Unable to authenticate to ECR to negotiate images"
      exit -1
  end
  docker_endpoint = ecrauth.authorization_data.first.proxy_endpoint.slice(8..-1) # chop off https://
  
  %w{backend }.each do |t|

    start_command = if t =~ /front/
<<-EOH
mv /frontend/frontend/ /frontend/frontend.real
(cat > /frontend/frontend) <<-EOF
#!/bin/sh
./frontend.real -backend $BACKEND
EOF
chmod +x /frontend/frontend
/sbin/my_init
EOH
    else
      ['/sbin/my_init']
    end

    backend = if t =~ /front/
      "BACKEND="
    end

    resources("#{t}_task_definition".to_sym) do
      type "AWS::ECS::TaskDefinition"
      properties do
        container_definitions [
          {
            'Name': t,
            'Image': "#{docker_endpoint}/#{t}:0.2",
            'Memory': 128,
            'Cpu': 10,
            'Command': start_command,
      #      'Environment': [ join!('BACKEND=', attr!("backend_service",""))],
            'PortMappings': [
                {
                  'ContainerPort': 80,
                  'HostPort': 0
                }
              ]
          }
        ]
        family t
        network_mode 'bridge'
      end
    end

    if t =~ /front/
      resources("#{t}_alb") do
        type 'AWS::ElasticLoadBalancingV2::LoadBalancer'
        properties do
          scheme 'internet-facing'
          subnets registry!(:zones).collect{|zone| "private_#{zone.gsub('-','_')}_subnet"}
          security_groups [ref!(:ecs_security_group)]
        end
      end

      resources("#{t}_alb_listener") do
        type 'AWS::ElasticLoadBalancingV2::Listener'
        properties do
          default_actions [{'Type': 'forward', 'TargetGroupArn': ref!("#{t}_target_group")}]
          load_balancer_arn ref!("#{t}_alb")
          port '80'
          protocol 'HTTP'
        end
      end
      
      resources("#{t}_target_group") do
        type 'AWS::ElasticLoadBalancingV2::TargetGroup'
        depends_on "#{t}_alb"
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

      resources("#{t}_scaling_target") do
        type 'AWS::ApplicationAutoScaling::ScalableTarget'
        depends_on "#{t}_service"
        properties do
          role_arm ref!(:iam_ecs_role)
          scalable_dimension 'ecs:service:DesiredCount'
          service_name_space 'ecs'
          resource_id join!('service/', ref!(:ecs_cluster), '/', attr!("#{t}_service", :name))
        end
      end

      #resources("#{t}_scaling_policy") do
      #  type 'AWS::ApplicationAutoScaling::ScalingPolicy'
      #  properties do
      #    policy_type 'StepScaling'
      #    scaling_target_id ref!("#{t}_scaling_target".to_sym)
      #    step_scaling_policy_configuration do
      #      adjustment_type 'PercentChangeInCapacity'
      #      cooldown        10
      #      metric_aggregation_type 'Average'
      #      step_adjustments [ {'MetricIntervalLowerBount':0, 'ScalingAdjustment': 200}]
      #    end
      #  end
      #end
    end

    resources("#{t}_service") do
      count = if t =~ /back/
        1
      else
        3
      end
      type 'AWS::ECS::Service'
      depends_on('backend_service') if t =~ /front/
      properties do
        cluster ref!(:ecs_cluster)
        desired_count count
        task_definition ref!("#{t}_task_definition".to_sym)
        if t =~ /front/
          role ref!(:ecs_iam_role)
          load_balancers [{'ContainerName': t, 'ContainerPort': 80, 'TargetGroupArn': ref!("#{t}_target_group") }]
        end
      end
    end
  end
end
