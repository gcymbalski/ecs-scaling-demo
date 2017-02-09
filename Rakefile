require 'json'
cfgfile = '.clustercfg'
cfg = if File.exist?(cfgfile)
  JSON.parse(File.read(cfgfile))
      else
          {}
      end

%w{AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID}.each do |e|
  if ENV[e].empty?
    puts "#{e} is not defined in your environment, please set it accordingly"
    exit -1
  end
end

desc 'Configure parameters for your cluster'
task :configure do
  require 'highline'
  #configure your cluster for use
  #  i.e. prompt the user for what the DNS name of the cluster should be
  cli = HighLine.new
  cname = cli.ask 'What should your cluster be reachable by? This will drive DNS updates on your service provider' do |q|
    q.default = cfg['cname']
  end
  cfg['cname'] = cname
  File.write(cfgfile, cfg.to_json)
end


namespace :build do
  desc 'Build images for cluster'
  task :artifacts do
    #wrap Packer's build of the images we need
  end

  desc 'Build a cluster'
  task :cluster do
    #use aforegenerated images to actually launch our cluster
  end
end

desc 'Test a running service cluster with ApacheBench locally'
task :test do
  if `which ab > /dev/null`
      puts "ApacheBench found, proceeding..."
  else
      puts "Cannot find ApacheBench (ab) in your PATH, please install it"
      exit -1
  end

  #wrap apachebench here
end
