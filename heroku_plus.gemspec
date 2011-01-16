# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "heroku_plus/version"

Gem::Specification.new do |s|
  s.name        = "heroku_plus"
  s.version     = HerokuPlus::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Brooke Kuhlmann"]
  s.email       = ["brooke@redalchemist.com"]
  s.homepage    = "http://www.redalchemist.com"
  s.summary     = "Enhances default Heroku functionality."
  s.description = "Enhances default Heroku functionality beyond what is provided with the Heroku gem."

  s.rdoc_options << "CHANGELOG.rdoc"
  s.required_ruby_version = "~> 1.8.7"
  s.add_dependency "heroku", ">= 1.0.0"
  s.add_development_dependency "rspec"
  s.executables << "hp"
  
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{|file| File.basename file}
  s.require_paths = ["lib"]
end
