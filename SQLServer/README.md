# SQLServer

Installs SQL Server and Provides for patching.

This cookbook works basically like this:
- By default, base settings are set via cookbook attributes (version=2014, features to install=SQLENGINE,CONN, instaled=MSSQLSERVER, etc.)
- You can override settings on a node-specific basis with knife node edit <nodename>, which will allow for different version to be installed, non-default instances, etc.
- If a node has a particular version installed, but doesn't have the latest patch installed, the patching section allows for that to happen as well, unless the no_patch attribute is set for a node

We're using this cookbook with node-specific Chef policies to control when things happen.
