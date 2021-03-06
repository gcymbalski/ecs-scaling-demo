# Initial Design Thoughts
- Fairly straightforward fault-tolerant* and auto-scaling** two-tier application with no other external dependencies (like auth, logging, databases- yay)
- Requires building and deploying both upstream applications and their build dependencies (i.e. Go) as well as container images:
  - Reasonably resolved by using Hashicorp's Packer to generate an intermediate image for building Go applications
    - Chef has well-maintained packages for cross-platform management of building Go development environments
    - And then we can build off that container to generate frontend and backend containers 
      - Or, in a perfect world, generate packages for frontend/backend services that then are deployed into fresh containers, avoiding any cruft incurred by the build environment/configuration management system/etc.
- Hard operational requirement of achieving a minimum of 50 reqs/s for a deployment reachable via a standard address (DNS, VIP, etc- which ELBs do nicely)
  - Backend (and singleton) service can support >>50 reqs/sec and a 2% non-critical (as in, the server doesn't die/need a restart) request failure rate
  - Frontend service can only manage around 10 reqs/sec in good cases- and crashes if backend service is unavailable
    - i.e. if it's not responding to GET requests from e.g. an ELB in AWS, terminate and respawn the failing instance/container

## Operational Concerns

My familiarity is with AWS, which makes me roughly envision this problem as a two-tier CloudFormation stack using a few other AWS resources, with most of the magic being around using their elastic load balancers and autoscaling groups. This ensures that applications are either alive and reporting in (as inferred from a 200 on GET /) or are respawned- plus lets you do other fancy AWS things, like get notifications on high failure rates and configure thresholds/algorithms around scaling (e.g. what times of day to scale up around? what kind of system load should we take as the impetus for spinning up additional nodes, and how many at a time?). This means that, operationally, bringing nodes online to serve traffic requires as few intermediate steps as possible- and doing multiple-availability zone load balancing even lets the backend service fail gracefully. Scaling that up and using multiple regions, presenting them with one consistent address via e.g. Route53 chosing a region more intelligently than simple round-robin. In the absence of other monitoring schemes, checking HTTP response codes is not a bad solution for detecting that nodes are online and capable of passing traffic, but it doesn't provide much more than a yes/no which has a potential for being false either way. Still, that's pretty useful for being such low-hanging fruit.

Another major concern is the decision to simply deploy containers that were also used to build the software being deployed- meaning there's some cruft that's not operationally necessary (and potentially even a liability). Plus, that means you're now tied to your container deployment technology for deployments rather than something more portable like system packages. Given additional infrastructure, I'd prefer the build infrastructure generate platform-specific packages (I use fpm for simplicity) from a standardized build environment image (or image set). Packages can be then checked in and made available to environment-specific repositories, making it easier to do promotional tests by virtue of more atomic change management. Best of all, if there are upstream dependencies in what our base image is (for example, I am a big fan of phusion's baseimage-docker project, which packages a more container-friendly small Ubuntu variant), we don't need to necessarily repeat the entire build chain to get a fresh, deployable image- all we need is to install the package we already have onto our updated container base (or switch to a new base entirely now that we're agnostic about it). 

##  Concerns

For simplicity, I am using my workstation running a modern Debian variant for development, working primarily in cross-platform tooling when possible. I'll be calling out dependencies and providing links to all tools required/used, including specific version information (e.g. using submodules for upstream deps, or Gemfiles that are more specific than usual).

The primary technologies I will be using are SparkleFormation, a DSL for managing CloudFormation-like stacks on various cloud providers, and Packer, a tool for generating images programmatically and flexibly.

## Artificial Testing

Using ApacheBench, we can test whether or not we are capable of reaching the desired throughput. We'll support wrapping this nicely to run from the user's workstation, but this means that the possibility of false negatives are raised (since not being able to hit 50reqs/sec from any arbitrary node could be caused by, for example, a poor user-side connection). Still, a positive is a good indicator.

Since the load balancers offered by AWS, GCE, and others give us a lot of freebies, we can easily observe request throughput service-side, as well.

## Organization

I'm a fan of tying things together with Rakefiles- you get some of the flexibility of writing a full-featured command-line application that is comparable to Make without the hassle of dealing with reinventing the wheel or frustrating people with potentially-unmaintainable Makefiles.

Functionally, the primary lifecycle of the cluster we need to operate looks like:
0. `rake cluster:init`: We deploy basic cluster infrastructure without running any tasks/containers, mostly so we can get a place to drop off our container images.
1. `rake cluster:artifacts`: We build container images using our local Docker installation, resulting in two images: one for the backend service, and one for the frontend. These are both committed into our Docker registry we just made if all goes well.
2. `rake cluster:build`: These container images are deployed into our cluster. At this point, testing is possible- by default, running load tests will spin up said cluster if not already created.
3. `rake cluster:destroy`: Finally, the cluster is able to be destroyed.

Running any of these tasks should handle the previous if they haven't been handled, enabling a user to run e.g. `rake test:throughput` and not even have to go through any of the initial stages. Still, a cluster must be explicitly destroyed.
