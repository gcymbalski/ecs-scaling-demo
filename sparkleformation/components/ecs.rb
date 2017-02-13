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
    end

    ecs_security_group do
      type 'AWS::EC2::SecurityGroup'
      properties do
        vpc_id ref!(:vpc_id)
        group_description 'allow access to ecs cluster hosts on all tcp ports'
        security_group_ingress _array(
        -> {
          ip_protocol 'tcp'
          from_port 22
          to_port 22
          cidr_ip ref!(:vpc_cidr)
        }
        )
      end
    end
  end

end
