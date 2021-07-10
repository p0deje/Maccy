ENV['VAGRANT_EXPERIMENTAL'] = 'typed_triggers'

Vagrant.configure('2') do |config|
  config.vm.define 'mojave' do |mj|
    mj.vm.box = 'yzgyyang/macOS-10.14'
    mj.vm.synced_folder '.', '/Users/vagrant/Desktop/Maccy', disabled: true
  end

  config.vm.define 'big-sur' do |bs|
    bs.vm.box = 'amarcireau/macos'
    bs.vm.synced_folder '.', '/vagrant', disabled: true
    bs.vm.provider 'virtualbox' do |v|
      v.check_guest_additions = false
    end
    bs.trigger.after 'VagrantPlugins::ProviderVirtualBox::Action::Import', type: :action do |t|
      t.ruby do |_env, machine|
        FileUtils.cp(
          machine.box.directory.join('include').join('macOS.nvram').to_s,
          machine.provider.driver.execute_command(['showvminfo', machine.id, '--machinereadable'])
            .split(/\n/)
            .map { |line| line.partition(/=/) }
            .select { |partition| partition.first == 'BIOS NVRAM File' }
            .last
            .last[1..-2]
        )
      end
    end
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.gui = true
    vb.memory = '8192'
  end
end
