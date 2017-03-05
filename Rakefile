require 'json'
require 'aws-sdk'
require 'pry'

CFGFILE = '.clustercfg'.freeze
DEBUG = ENV['DEBUG'] ? true : false
VPC_NAME = 'demo-service-vpc-base'.freeze
SERVICES_NAME = 'demo-service-vpc-containers'.freeze
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
    reply = cf.describe_stacks(stack_name: _stack_name)
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
  desc 'Test (alias for rake test)'
  task :test do
    Rake::Task['test:throughput'].invoke
  end

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

    writecfg(cfg)
  end

  desc 'Build artifacts remotely for cluster'
  task :remote_artifacts, [:force] do |_t, _args|
    Rake::Task['cluster:init'].invoke unless get_stack(VPC_NAME)
    manifest = 'container_images/manifest.json'
    if File.exist?(manifest)
      puts "Looks like you've run this successfully before; removing old manifest in 5 seconds, hit ctrl-c to bail out"
      sleep 5
      puts "Removing..."
      File.delete(manifest)
    end
    opts = ('-debug' if DEBUG)
    vpcstack = get_stack(VPC_NAME).to_h

    vpc_id = vpcstack[:outputs].select do |k|
               k[:output_key] == 'VpcId'
             end.first[:output_value]

    subnet_id = vpcstack[:outputs].select do |k|
               k[:output_key] =~ /Public.*Subnet/
             end.first[:output_value].split(',').first

    ecs_instance_profile = vpcstack[:outputs].select do |k|
              k[:output_key] == 'EcsInstanceProfile'
            end.first[:output_value]

            puts 'profile is ' + ecs_instance_profile

    ENV['AWS_VPC_ID'] = vpc_id
    ENV['AWS_SUBNET_ID'] = subnet_id
    ENV['AWS_INSTANCE_PROFILE'] = ecs_instance_profile
    status = system("cd container_images && packer build #{opts} container-build-host.json")
    if status && File.exist?(manifest)
      mfst = JSON.load(File.read(manifest))
      # This is a gross one-liner that reads into the manifest hash to see what ami we just created so we can remove it- right now, Packer can't optionally discard an Amazon build job, so it generates an AMI. Kinda nice for debugging, actually.
      ami = JSON.load(File.read('container_images/manifest.json'))['builds'].first['artifact_id'].split(':').last
      unless DEBUG || ( ENV['KEEP_AMI'] && ENV['KEEP_AMI'] != 0)
        ec2 = Aws::EC2::Client.new
        snapshot = ec2.describe_images(image_ids: [ami]).images.first.block_device_mappings.first.ebs.snapshot_id
        ec2.deregister_image(image_id: ami)
        ec2.delete_snapshot(snapshot_id: snapshot)
      else
        puts "Kept intermediate AMI: #{ami}"
      end
    else
      puts 'Failed to generate images!'
      exit -1
    end
  end

  desc 'Build images for cluster'
  task :artifacts, [:force] do |_t, args|
    # wrap Packer's build of the images we need, pushing to ECR
    #  - note that this is the only stage that specifically requires running on Linux, grr
    checkvars
    Rake::Task['cluster:init'].invoke if get_stack(VPC_NAME)
    ecrauth = Aws::ECR::Client.new.get_authorization_token
    unless ecrauth && ecrauth.authorization_data.first.proxy_endpoint
        puts "Couldn't figure out which remote Docker repository to commit to"
        exit -1
    end
    docker_endpoint = ecrauth.authorization_data.first.proxy_endpoint.slice(8..-1) # chop off https://
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
    Rake::Task['cluster:init'].invoke unless get_stack(VPC_NAME)
    ecr = Aws::ECR::Client.new
    if ecr.describe_images(repository_name: 'backend').image_details.empty? || ecr.describe_images(repository_name: 'frontend').image_details.empty?
      Rake::Task['cluster:remote_artifacts'].invoke
    end
    ecr = Aws::ECR::Client.new
    ecrauth = ecr.get_authorization_token
    unless ecrauth && ecrauth.authorization_data.first.proxy_endpoint
        puts "Couldn't figure out which remote Docker repository to commit to"
        exit -1
    end
    docker_endpoint = ecrauth.authorization_data.first.proxy_endpoint.slice(8..-1) # chop off https://
    # now we have an image path, sort of
    vpcstack = get_stack(VPC_NAME)

    vpc_id   = vpcstack[:outputs].select do |k|
                 k[:output_key] == 'VpcId'
               end.first[:output_value]

    subnets = vpcstack[:outputs].select do |k|
      k[:output_key] =~ /Public.*Subnet/
    end
    subnet_vars = subnets.collect { |x| "#{x[:output_key]}:#{x[:output_value]}" }.join(',')

    cfg = readcfg

    svcs = get_stack(SERVICES_NAME)
    unless svcs
      status = system("sfn create -d #{SERVICES_NAME} --file sparkleformation/ecs.rb --apply-stack #{VPC_NAME}")
      unless status
        puts 'Failed generating our ECS stack!'
        exit -1
      end
      uri = svcs[:outputs].select do |k|
               k[:output_key] == 'FrontendAlbDns'
             end.first[:output_value]
      puts 'Generated services on our ECS cluster- frontend load balancer DNS:'
      puts "http://#{uri}/"
    end
    writecfg(cfg)
  end

  desc 'Tear down cluster'
  task :terminate do
    checkvars
    cfg = readcfg
    # first, empty our container repos
    ecr = Aws::ECR::Client.new
    repos = ecr.describe_repositories.repositories.select{|x| %w(frontend backend).include?(x.repository_name)}.collect{|x|x['repositoryName']}
    repos.each do |repo|
      digests = ecr.describe_images(repository_name: repo)
      if digests
          digests = digests.image_details.collect { |x| { 'image_digest' => x['image_digest'] } }
          ecr.batch_delete_image(repository_name: repo, image_ids: digests)
      end
    end
    puts 'Emptied remote repositories...'
    # then we can be done with all our stacks
    status = system("sfn destroy #{SERVICES_NAME}; sfn destroy #{VPC_NAME}")
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
    Rake::Task['cluster:init'].invoke unless get_stack(VPC_NAME)
    Rake::Task['cluster:build'].invoke unless get_stack(SERVICES_NAME)

    svcs = get_stack(SERVICES_NAME).to_h
    unless svcs 
      puts "Unable to find running stacks with load balancer; something went wrong, try terminating and retrying"
      exit -1
    end
    uri = svcs[:outputs].select do |k|
               k[:output_key] == 'FrontendAlbDns'
             end.first[:output_value]

    system("ab -r -n 1500 -c 5 http://#{uri}/")
  end
end
