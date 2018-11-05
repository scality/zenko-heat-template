# zenko-murano-app
An OpenStack Murano script to deploy Zenko on MetalK8s on an OpenStack cloud.
The Stack/Application deploys the required minimum system to run Zenko. By default, it does not deploy anything else than the instances, but it can be configured to install Metalk8s only, or Metalk8s And Zenko.

# CLI Usage
This assumes that you have a functioning environment with openstack CLI tool able to run against your openstack environment.</br>

## Deploying the template only
openstack stack create --parameter key_name=<key_to_use> --parameter network=<network> -t template.yaml <stackname>

## Deploying the template and metalk8s only
openstack stack create --parameter key_name=<key_to_use> --parameter install=metalk8sonly --parameter zenko_version=1.0.1 --parameter network=<network> -t template.yaml <stackname>

## Deploying the full stack (instances, metalk8s and Zenko)
openstack stack create --parameter key_name=<key_to_use> --parameter install=both --parameter zenko_version=1.0.1 --parameter network=<network> -t template.yaml <stackname>

# Murano Packages
The included script, *create-nurano-package.sh*, will generate a zip file that can be used to deploy the stack as well. the Platform9 UI allows creating applications based on murano packages, which can then be used to deploy zenko/metalk8s as an application tby all your authorized platform9 users.