#
# Credit: https://gist.github.com/RulerOf/b9f5dd00a9911aba8271b57d3d269d7a
#
class Arn
  attr_accessor :partition, :service, :region, :account, :resource

  def initialize(partition, service, region, account, resource)
    @partition = partition
    @service = service
    @region = region
    @account = account
    @resource = resource
  end

  def self.parse(arn)
    raise TypeError, 'ARN must be supplied as a string' unless arn.is_a?(String)

    arn_components = arn.split(':', 6)
    raise ArgumentError, 'Could not parse ARN' if arn_components.length < 6

    Arn.new arn_components[1],
            arn_components[2],
            arn_components[3],
            arn_components[4],
            arn_components[5]
  end
end
