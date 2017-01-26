#
# Cookbook Name:: SQLServer
# Recipe:: sqlserver
#

#create the sqlinstall directory if it doesn't already exist
directory 'c:\\sqlinstall' do
  action :create
end

#pull down the encryption key used to decrypt our SQL SA password - might want to switch this up to chef vault at some point
#uses the .run_action(:create) syntax to define this resource as a compile time resource
#per https://getchef.zendesk.com/hc/en-us/articles/209245786-Compile-vs-Converge-Time-Encrypted-Databag-Read
remote_file "c:/chef/SQLServerChefDataBagKey.pem" do
  source "https://internalrepo.mydomain.com/Chef/SQLServer/SQLServerChefDataBagKey.pem"
  action :create_if_missing
end.run_action(:create)

#grab the sa and chef passwords from the SQLServer data bag
sa = data_bag_item('SQLServer', 'sa', IO.read('c:/chef/SQLServerChefDataBagKey.pem'))
chef = data_bag_item('SQLServer', 'chef', IO.read('c:/chef/SQLServerChefDataBagKey.pem'))

#only perform install steps for versions later than 2012 - we're not installing 2008r2 or below anymore
if node['sqlserver']['version'] == '2012' or node['sqlserver']['version'] == '2014' or node['sqlserver']['version'] == '2016'
  #build the config file for SQL
  template "c:\\sqlinstall\\SQLConfigurationFile.ini" do
    source 'SQLConfigurationFile.ini.erb'
    variables({
      :sqlAdmin => node[:sqlserver][:administrator],
      :sqlFeatures => node[:sqlserver][:sqlFeatures],
      :saPassword => sa['password']
    })
  end

  node['sqlserver']['instances'].each do |i| 
    powershell_script "InstallSQLServer_#{i}" do
      timeout 600000
      code <<-EOH
        #copy the install files locally
        Invoke-WebRequest -Uri "https://internalrepo.mydomain.com/chef/SQLServer/SQL#{node[:sqlserver][:version]}.zip" -OutFile "c:\\sqlinstall\\SQL#{node[:sqlserver][:version]}.zip"
        $backupPath = "c:\\sqlinstall\\SQL#{node[:sqlserver][:version]}.zip"
        $destination = "c:\\sqlinstall"
        Add-Type -assembly "system.io.compression.filesystem"
        [io.compression.zipfile]::ExtractToDirectory($backupPath, $destination)
      
        $installDirectory = "c:\\sqlinstall\\#{node[:sqlserver][:version]}"
        $SQLConfigurationFile = "c:\\sqlinstall\\SQLConfigurationFile.ini"
        
        #Check to see if the system has a d: drive and use that for the SQL drives. If not, fallback to c:
        $fixedDrives = [System.IO.DriveInfo]::getdrives() | Where-Object {$_.DriveType -eq 'Fixed'}
        $dDriveFound = 0
        foreach ($d in $fixedDrives) {
           if ($d.Name -eq 'D:\\') { $dDriveFound = 1 }
        }

        if ($dDriveFound -eq 1) {
           $installDrive = "d:"
        } else {
           $installDrive = "c:"
        }
        
        $INSTALLSHAREDDIR= $installDrive + "\\Program Files\\Microsoft SQL Server"
        $INSTALLSHAREDWOWDIR= $installDrive + "\\Program Files (x86)\\Microsoft SQL Server"
        $INSTANCEDIR= $installDrive + "\\Program Files\\Microsoft SQL Server"
        $INSTALLSQLDATADIR= $installDrive + "\\Program Files\\Microsoft SQL Server"
        
        #if the instance is MSSQLSERVER, use the default names. Else use the Instance-specific names
        if ("#{i}" -eq "MSSQLSERVER") {
          $serviceAccount = 'NT SERVICE\\MSSQLSERVER'
          $agentServiceAccount = 'NT SERVICE\\SQLSERVERAGENT'
        } else {
          $serviceAccount = "NT SERVICE\\MSSQL`$#{i}"
          $agentServiceAccount = "NT SERVICE\\SQLAGENT`$#{i}"
        }

        # run the installer using the ini file
        Start-Process -Wait "$installDirectory\\Setup.exe" "/Q /ACTION=INSTALL /IACCEPTSQLSERVERLICENSETERMS /INSTALLSHAREDDIR=""$INSTALLSHAREDDIR"" /INSTALLSHAREDWOWDIR=""$INSTALLSHAREDWOWDIR"" /INSTANCEDIR=""$INSTANCEDIR"" /INSTANCEID=""#{i}"" /INSTANCENAME=""#{i}"" /AGTSVCACCOUNT=""$agentServiceAccount"" /INSTALLSQLDATADIR=""$INSTALLSQLDATADIR"" /SQLSVCACCOUNT=""$serviceAccount"" /UpdateEnabled=TRUE /UpdateSource=""$installDirectory\\updates"" /CONFIGURATIONFILE=""$SQLConfigurationFile"""
        
        #remove the source files
        Remove-Item $backupPath
        Remove-Item "c:\\sqlinstall\\#{node[:sqlserver][:version]}" -Force -Recurse
        
        #sleep 30 seconds for SQL Server services to start
        Start-Sleep -s 30
      EOH
      notifies :run, "powershell_script[AddChefUser_#{i}]", :immediately
      guard_interpreter :powershell_script
      not_if "$instance = gwmi win32_service -computerName localhost | ? { $_.Name -match '#{i}' -and $_.PathName -match 'sqlservr.exe' -and $_.Caption -eq 'SQL Server (#{i})' }; if ($instance) { return $true } else { return $false }"
    end
    
    if "#{i}" != 'MSSQLSERVER'
      service 'SQLBrowser' do
        action [:enable, :start]
      end
    end

    #this should only run on new installs
    powershell_script "AddChefUser_#{i}" do
      environment ({'sa' => sa['password'], 'chef' => chef['password']})
      code <<-EOH
        if ("#{i}" -eq "MSSQLSERVER") {
          $instance = 'localhost'
        } else {
          $instance = $env:computername + "\\#{i}"
        }
        
        switch (#{node[:sqlserver][:version]}) {
          '2012' {
            $SQLPSModuleLocation = "C:\\Program Files (x86)\\Microsoft SQL Server\\120\\Tools\\PowerShell\\Modules\\"
          }
          '2014' {
            $SQLPSModuleLocation = "C:\\Program Files (x86)\\Microsoft SQL Server\\120\\Tools\\PowerShell\\Modules\\"
          }
          '2016' {
            $SQLPSModuleLocation = "C:\\Program Files (x86)\\Microsoft SQL Server\\130\\Tools\\PowerShell\\Modules\\"
          }
        }
        
        $env:PSModulePath = $env:PSModulePath + ";" + $SQLPSModuleLocation
        
        Import-Module SQLPS
        $chefLoginExists = Invoke-SQLCmd -ServerInstance $instance -Username sa -Password $env:sa "select name from sys.syslogins where name = 'chef'"
        if (-not $chefLoginExists) {
           Invoke-SQLCmd -ServerInstance $instance -Username sa -Password $env:sa "create login chef with password = '$env:chef'"
           Invoke-SQLCmd -ServerInstance $instance -Username sa -Password $env:sa "ALTER SERVER ROLE sysadmin ADD MEMBER chef"
        }
      EOH
      action :nothing
      guard_interpreter :powershell_script
    end
  end
  
  powershell_script 'SQLFirewallRule' do
    code <<-EOH
      New-NetFirewallRule -DisplayName 'SQL Server (1433)' -Direction Inbound -Action Allow -LocalPort 1433 -Protocol TCP
    EOH
    guard_interpreter :powershell_script
    not_if "Get-NetFirewallRule -DisplayName 'SQL Server (1433)' -ErrorAction SilentlyContinue | Out-Null; $?"
  end
end

######################## PATCHING SECTION ########################
if node['sqlserver']['no_patch'] != '1'
  #apply the sp3 patch if sql2008r2 is applied and the host doesn't have sp3 yet - uses "rescue" to catch the exception for the node attribute not existing yet
  if node['sqlserver']['version'] == '2008R2' and node['packages']['Microsoft SQL Server 2008 R2 Setup (English)']['version'] != '10.53.6000.34'
    powershell_script 'SQL2008R2SP3' do
      code <<-EOH
        #copy the install files locally
        Invoke-WebRequest -Uri "https://internalrepo.mydomain.com/chef/SQLServer/SQLServer2008R2SP3-KB2979597-x64-ENU.exe" -OutFile "c:\\sqlinstall\\SQLServer2008R2SP3-KB2979597-x64-ENU.exe"
        
        Start-Process -Wait "c:\\sqlinstall\\SQLServer2008R2SP3-KB2979597-x64-ENU.exe" "/allinstances /quiet /IACCEPTSQLSERVERLICENSETERMS"
        
        Remove-Item "c:\\sqlinstall\\SQLServer2008R2SP3-KB2979597-x64-ENU.exe"
      EOH
    guard_interpreter :powershell_script
    end
  end rescue NoMethodError

  #apply the sp3 patch if sql2012 is applied and the host doesn't have sp3 yet - uses "rescue" to catch the exception for the node attribute not existing yet
  if node['sqlserver']['version'] == '2012' and node['packages']['Microsoft SQL Server 2012 Setup (English)']['version'] != '11.3.6020.0'
    powershell_script 'SQL2012SP3' do
      code <<-EOH
        #copy the install files locally
        Invoke-WebRequest -Uri "https://internalrepo.mydomain.com/chef/SQLServer/SQLServer2012SP3-KB3072779-x64-ENU.exe" -OutFile "c:\\sqlinstall\\SQLServer2012SP3-KB3072779-x64-ENU.exe"
        
        Start-Process -Wait "c:\\sqlinstall\\SQLServer2012SP3-KB3072779-x64-ENU.exe" "/allinstances /quiet /IACCEPTSQLSERVERLICENSETERMS"
        
        Remove-Item "c:\\sqlinstall\\SQLServer2012SP3-KB3072779-x64-ENU.exe"
      EOH
    guard_interpreter :powershell_script
    end
  end rescue NoMethodError

  #apply the sp2 patch if sql2014 is applied and the host doesn't have sp2 yet - uses "rescue" to catch the exception for the node attribute not existing yet
  if node['sqlserver']['version'] == '2014' and node['packages']['Microsoft SQL Server 2014 Setup (English)']['version'] != '12.2.5000.0'
    powershell_script 'SQL2014SP2' do
      code <<-EOH
        #copy the install files locally
        Invoke-WebRequest -Uri "https://internalrepo.mydomain.com/chef/SQLServer/SQLServer2014SP2-KB3171021-x64-ENU.exe" -OutFile "c:\\sqlinstall\\SQLServer2014SP2-KB3171021-x64-ENU.exe"
      
        Start-Process -Wait "c:\\sqlinstall\\SQLServer2014SP2-KB3171021-x64-ENU.exe" "/allinstances /quiet /IACCEPTSQLSERVERLICENSETERMS"
        
        Remove-Item "c:\\sqlinstall\\SQLServer2014SP2-KB3171021-x64-ENU.exe"
      EOH
    guard_interpreter :powershell_script
    end
  end rescue NoMethodError
end
