require 'json'
CFGFILE = '.clustercfg'.freeze
DEBUG = ENV['DEBUG'] ? true : false

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

    writecfg(cfg)
  end

  desc 'Build images for cluster'
  task :artifacts, [ :force ] do |_t, args|
    # wrap Packer's build of the images we need, pushing to ECR
    #  - note that this is the only stage that specifically requires running on Linux, grr
    checkvars
    puts 'Generating images, please wait...'
    opts = ('-debug' if DEBUG)
    cfg = readcfg
    %w(
      01-container-base.json
      02-container-golang.json
      03-container-backend-webservice.json
      04-container-frontend-webservice.json
    ).each do |step|
      if ( ! args[:force]) && cfg['artifacts'][step]
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
    puts "Successfully built images!"
    writecfg(cfg)
  end

  desc 'Build cluster services'
  task :build do
    checkvars
    # use aforegenerated images to actually launch our cluster
    cfg = readcfg

    writecfg(cfg)
  end

  desc 'Tear down cluster'
  task :terminate do
    checkvars
    # kill the whole thing
    cfg = readcfg

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
    # wrap apachebench here
    cfg = readcfg

    writecfg(cfg)
  end
end
