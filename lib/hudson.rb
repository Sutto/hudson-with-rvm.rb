module Hudson
  VERSION        = "0.2.6"
  HUDSON_VERSION = "1.371"
  WAR            = File.expand_path(File.dirname(__FILE__) + "/hudson/hudson.war")
  PLUGINS        = File.expand_path(File.dirname(__FILE__) + "/hudson/plugins")
end

require 'hudson/api'
require 'hudson/job_config_builder'
require 'hudson/project_scm'
