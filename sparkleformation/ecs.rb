SparkleFormation.new(:ecs).load(:base).overrides do

  parameters do
    vpc_id do
      type 'String'
      description 'VPC to Join'
    end
  end
  
  resources do
    security_group do
      type 'AWS::EC2::SecurityGroup'
      properties do
        group_description "Security Group for Example"
        vpc_id ref!(:vpc_id)
      end
    end
    
    http_security_group_ingress do
      type 'AWS::EC2::SecurityGroupIngress'
      properties do
        group_id ref!(:security_group)
        ip_protocol 'tcp'
        from_port 80
        to_port 80
        cidr_ip '0.0.0.0/0'
      end
    end

    all_security_group_egress do
      type 'AWS::EC2::SecurityGroupEgress'
      properties do
        group_id ref!(:security_group)
        ip_protocol '-1'
        from_port 1
        to_port 65535
        cidr_ip '0.0.0.0/0'
      end
    end
   
    ecr_repository do
      type 'AWS::ECR::Repository'
    end

    ecs_cluster do
      type 'AWS::ECS::Cluster'
    end   
  end

  outputs do
    ecr_endpoint do
      description 'ECR endpoint for Docker repository operations'
      value ref!(:ecr_repository)
    end
  end
end
