# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "heroku_plus/version"

Gem::Specification.new do |s|
  s.name                  = "heroku_plus"
  s.version               = HerokuPlus::VERSION
  s.platform              = Gem::Platform::RUBY
  s.author                = "Brooke Kuhlmann"
  s.email                 = "brooke@redalchemist.com"
  s.homepage              = "http://www.redalchemist.com"
  s.summary               = "Enhances default Heroku functionality."
  s.description           = "Enhances default Heroku functionality beyond what is provided with the Heroku gem."
  s.license               = "MIT"
  s.post_install_message	= "(W): www.redalchemist.com. (T): @ralchemist."

  s.rdoc_options << "CHANGELOG.rdoc"
  s.required_ruby_version = "~> 1.9.0"
  s.add_dependency "thor", "~> 0.14.0"
  s.add_dependency "thor_plus", ">= 0.1.0"
  s.add_dependency "heroku", ">= 2.0.0"
  s.add_development_dependency "rspec"
  s.add_development_dependency "aruba"
  s.executables << "hp"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{|file| File.basename file}
  s.require_paths = ["lib"]
end
