Vagrant.configure('2') do |config|
  config.vm.define 'high-sierra' do |hs|
    hs.vm.box = 'thealanberman/macos-10.13.4'
    hs.vm.synced_folder '.', '/Users/vagrant/Desktop/Maccy', type: 'rsync'
  end

  config.vm.define 'mojave' do |mj|
    mj.vm.box = 'yzgyyang/macOS-10.14'
    mj.vm.synced_folder '.', '/Users/vagrant/Desktop/Maccy', disabled: true
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.gui = true
    vb.memory = '4096'
  end
end
