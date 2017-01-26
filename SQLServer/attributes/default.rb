default[:sqlserver][:version] = '2014'
default[:sqlserver][:administrator] = 'MYDOMAIN\\MYDBAGROUP'
default[:sqlserver][:sqlFeatures] = 'SQLENGINE,CONN'
default[:sqlserver][:instances] = ['MSSQLSERVER']
default[:sqlserver][:no_patch] = '0' #used to allow prevention of patches to nodes