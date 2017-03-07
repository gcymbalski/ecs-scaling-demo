SparkleFormation.new(:cluster_vpc, inherit: :lazy_vpc__nat_subnet_vpc).load(:ecs).overrides do
end
