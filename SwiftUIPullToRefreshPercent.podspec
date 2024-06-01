Pod::Spec.new do |s|
  s.name                  = 'SwiftUIPullToRefreshPercent'
  s.version               = '3.0.0'
  s.summary               = 'Pull to refresh on any SwiftUI Scroll View.'
  s.homepage              = 'https://github.com/Pikuseru/swiftui-pull-to-refresh-percent'
  s.license               = { :type => 'MIT', :file => 'LICENSE' }
  s.author                = { 'Gordan Glavaš' => 'gordan.glavas@gmail.com', 'Dave Birdsall' => 'dave.birdsall@gmail.com' }
  s.source                = { :git => 'https://github.com/Pikuseru/swiftui-pull-to-refresh-percent.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'
  s.source_files          = 'Sources/SwiftUIPullToRefreshPercent/**/*'
end
