SparkleFormation.component(:vpc) do

  parameters(:vpc_cidr) do
    description 'VPC Subnet'
    type 'String'
    default '10.0.0.0/16'
  end

  parameters(:dns_support) do
    description 'Enable VPC DNS Support'
    type 'String'
    default 'true'
    allowed_values %w(true false)
  end

  parameters(:dns_hostnames) do
    description 'Enable VPC DNS Hostname Support'
    type 'String'
    default 'true'
    allowed_values %w(true false)
  end

  parameters(:instance_tenancy) do
    description 'Enable VPC Instance Tenancy'
    type 'String'
    default 'default'
    allowed_values %w(default dedicated)
  end

  resources(:dhcp_options) do
    type 'AWS::EC2::DHCPOptions'
    properties do
      domain_name 'ec2.internal'
      domain_name_servers ['AmazonProvidedDNS']
      tags _array(
        -> {
          key 'Name'
          value stack_name!
        }
      )
    end
  end

  resources(:vpc) do
    type 'AWS::EC2::VPC'
    properties do
      cidr_block ref!(:vpc_cidr)
      enable_dns_support ref!(:dns_support)
      enable_dns_hostnames ref!(:dns_hostnames)
      instance_tenancy ref!(:instance_tenancy)
      tags _array(
        -> {
          key 'Name'
          value stack_name!
        }
      )
    end
  end

  resources(:vpc_dhcp_options_association) do
    type 'AWS::EC2::VPCDHCPOptionsAssociation'
    properties do
      vpc_id ref!(:vpc)
      dhcp_options_id ref!(:dhcp_options)
    end
  end

  %w( public ).each do |type|
    resources("#{type}_route_table".to_sym) do
      type 'AWS::EC2::RouteTable'
      properties do
        vpc_id ref!(:vpc)
        tags _array(
          -> {
            key 'Name'
            value join!(stack_name!, " #{type}")
          }
        )
      end
    end
  end

  resources(:nat_eip) do
    type 'AWS::EC2::EIP'
    properties do
      domain 'vpc'
    end
  end

  resources(:nat_gateway) do
    type 'AWS::EC2::NatGateway'
    depends_on process_key!('nat_eip')
    properties do
      allocation_id attr!(:nat_eip, :allocation_id)
      subnet_id ref!(registry!(:zones).collect{|z| "public_#{z.gsub('-','_')}_subnet" }.first.to_sym)
    end
  end

  resources(:nat_route) do
    type 'AWS::EC2::Route'
    depends_on process_key!('nat_gateway')
    properties do
      destination_cidr_block '0.0.0.0/0'
      nat_gateway_id ref!(:nat_gateway)
      route_table_id ref!(:public_route_table)
    end
  end

  outputs(:vpc_id) do
    value ref!(:vpc)
  end

  [ :vpc_cidr, :nat_route, :nat_gateway ].each do |x|
    outputs do
      set!(x) do
        value ref!(x)
      end
    end
  end

end
