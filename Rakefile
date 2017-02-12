require 'json'
require 'aws-sdk'
require 'pry'

CFGFILE = '.clustercfg'.freeze
DEBUG = ENV['DEBUG'] ? true : false
VPC_NAME = 'ecs-cluster'.freeze
ENV['AWS_DEFAULT_REGION'] = ENV['AWS_REGION']

def readcfg
  if File.exist?(CFGFILE)
    JSON.parse(File.read(CFGFILE))
  else
    {}
  end
end

def writecfg(cfg)
  File.write(CFGFILE, cfg.to_json)
end

def get_stack(_stack_name)
  cf = Aws::CloudFormation::Client.new
  begin
    reply = cf.describe_stacks(stack_name: VPC_NAME)
    stack = reply.stacks.select do |stk|
      # reasonable assumption we've got the right stack here
      stk.stack_status =~ /COMPLETE/ && \
           ! (stk.stack_status =~ /DELETE/)
    end
    if stack.count == 1
      stack.first
    else
      nil
    end
  rescue Aws::CloudFormation::Errors::ValidationError
    nil
  end
end

def checkvars
  %w(AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID AWS_REGION).each do |e|
    if ENV[e] && ENV[e].empty?
      puts "#{e} is not defined in your environment, please set it accordingly"
      exit -1
    end
  end
end

namespace :cluster do
  desc 'Preflight stuff- check out submodules, upstream Chef artifacts, etc'
  task :preflight do
    checkvars
    puts 'Updating submodules...'
    success = system('git submodule init; git submodule update')
    puts 'Grabbing upstream Chef artifacts...'
    success &&= system('cd container_images/chef && librarian-chef install')
    unless success
      puts 'Unable to fetch upstream artifacts!'
      exit -1
    end
  end

  desc 'Initialize a cluster (i.e. get an ECR endpoint available)'
  task :init do
    Rake::Task['cluster:preflight'].invoke
    # call first-stage sparkle templates
    cfg = readcfg
    unless get_stack(VPC_NAME)
      puts "Building a stack with SparkleFormation..."
      debugstring = DEBUG ? '-u' : ''
      runline = "sfn create #{debugstring} -d #{VPC_NAME} --file sparkleformation/vpc.rb"
      status = system(runline)
      unless status
        puts 'Failed generating our VPC!'
        exit -1
      end
    end

    vpcstack = get_stack(VPC_NAME)

    vpc_id   = vpcstack[:outputs].select do |k|
                 k[:output_key] == 'VpcId'
               end.first[:output_value]

    unless get_stack('ecs')
      status = system("sfn create -m vpc_id:#{vpc_id} -d ecs --file sparkleformation/ecs.rb")
      unless status
        puts 'Failed generating our ECS stack!'
        exit -1
      end
    end
    writecfg(cfg)
  end

  desc 'Build artifacts remotely for cluster'
  task :remote_artifacts, [:force] do |_t, _args|
    Rake::Task['cluster:init'].invoke unless get_stack(VPC_NAME)
    opts = ('-debug' if DEBUG)
    vpcstack = get_stack(VPC_NAME).to_h

    vpc_id = vpcstack[:outputs].select do |k|
               k[:output_key] == 'VpcId'
             end.first[:output_value]

    subnet_id = vpcstack[:outputs].select do |k|
                  k[:output_key] =~ /Public.*Subnet/
                end.first[:output_value]

    ENV['AWS_VPC_ID'] = vpc_id
    ENV['AWS_SUBNET_ID'] = subnet_id
    status = system("cd container_images && packer build #{opts} container-build-host.json")
  end

  desc 'Build images for cluster'
  task :artifacts, [:force] do |_t, args|
    # wrap Packer's build of the images we need, pushing to ECR
    #  - note that this is the only stage that specifically requires running on Linux, grr
    checkvars
    Rake::Task['cluster:init'].invoke if get_stack(VPC_NAME)
    docker_endpoint = `aws ecr get-login`.split.last.slice(8..-1) # chop off https://
    ENV['DOCKER_LOGIN_SERVER'] = docker_endpoint
    puts 'Generating images, please wait...'
    opts = ('-debug' if DEBUG)
    cfg = readcfg
    cfg['artifacts'] ||= {}
    %w(
      01-container-base.json
      02-container-golang.json
      03-container-backend-webservice.json
      04-container-frontend-webservice.json
    ).each do |step|
      if (!args[:force]) && cfg['artifacts'][step]
        puts "Skipping step #{step}, force with `rake cluster:artifacts[force]`"
        next
      end
      status = system("cd container_images && packer build #{opts} #{step}")
      unless status
        puts "Failed to build #{step}, please debug further (export DEBUG=true for more)"
        exit -1
      end
      cfg['artifacts'][step] = true
    end
    puts 'Successfully built images!'
    writecfg(cfg)
  end

  desc 'Build cluster services'
  task :build do
    # use aforegenerated images to actually launch our cluster
    Rake::Task['cluster:init'].invoke if get_stack(VPC_NAME)
    vpcstack = get_stack(VPC_NAME)

    vpc_id   = vpcstack[:outputs].select do |k|
                 k[:output_key] == 'VpcId'
               end.first[:output_value]

    subnets = vpcstack[:outputs].select do |k|
      k[:output_key] =~ /Public.*Subnet/
    end
    subnet_vars = subnets.collect { |x| "#{x[:output_key]}:#{x[:output_value]}" }.join(',')

    cfg = readcfg
    # XXX future stack update that
    #    status = system("sfn create -m vpc_id:#{vpc_id} -d ecs --file sparkleformation/ecs.rb")
    writecfg(cfg)
  end

  desc 'Tear down cluster'
  task :terminate do
    checkvars
    cfg = readcfg
    # first, empty our container repos
    ecr = Aws::ECR::Client.new
    %w(backend frontend).each do |repo|
      digests = ecr.describe_images(repository_name: repo).image_details.collect { |x| { 'image_digest' => x['image_digest'] } }
      ecr.batch_delete_image(repository_name: repo, image_ids: digests)
    end
    puts 'Emptied remote repositories...'
    # then we can be done with all our stacks
    status = system("sfn destroy ecs && sfn destroy #{VPC_NAME}")
    writecfg(cfg)
  end
end

namespace :test do
  desc 'Test throughput against a running service cluster with ApacheBench locally'
  task :throughput do
    if `which ab > /dev/null`
      puts 'ApacheBench found, proceeding...'
    else
      puts 'Cannot find ApacheBench (ab) in your PATH, please install it'
      exit -1
    end
    Rake::Task['cluster:init'].invoke if get_stack(VPC_NAME)
    vpcstack = get_stack(VPC_NAME)
    # wrap apachebench here
    cfg = readcfg

    writecfg(cfg)
  end
end
