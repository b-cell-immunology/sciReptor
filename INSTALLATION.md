sciReptor Installation Manual
=============================

Host Installation
-----------------

The following section covers the installation of a virtual machine capable of running sciReptor. In case you are performing a direct installation
(i.e. without a virtualization layer), there will some of instruction you can omit, but otherwise the procedure is identical. The workflow described
here was used to generate the [pre-build sciReptor VM](http://b-cell-immunology.dkfz.de/sciReptor_VMs/). The VM supervisor used is
[Virtual Box 5.0](https://www.virtualbox.org/wiki/Download_Old_Builds_5_0), which is available for most commonly used operating systems. The
following resources should be considered the minimum requirements, recommend would be the double amount of everything (except network adapters):

* CPU cores: 4
* RAM : 8 GB
* storage: 8 GB
* network: 1 adapter (NAT)

Through-out the installation there will always be two user accounts:

* _root_ (password "root"): administration user
* _scireptor_ (no password): normal user

The base Linux system used is a [CentOS 7.1](http://isoredirect.centos.org/centos/7/isos/x86_64/CentOS-7-x86_64-Everything-1503-01.iso). 

1. Start empty VM which CentOS 7.1 boot medium (CentOS-7-x86_64-Everything-1503-01.iso, SHA256 checksum:
   8c3f66efb4f9a42456893c658676dc78fe12b3a7eabca4f187de4855d4305cc7)
2. Language: English-US
3. Configuration: **Minimal install**, single volume & partition storage (size as noted above), Network device activated
4. Start install
5. Set password "root" for user _root_
6. Create additional user _scireptor_, set empty password, activate "user is administrator"
7. Wait for installation to complete, then "Finish install" and Reboot
8. Login as user _scireptor_ (it is assume that you do this everytime from now on)
9. Update machine using `sudo yum update`
10. Reboot
11. Install additional repository and tools: `sudo yum install epel-release redhat-lsb kernel-devel gcc bzip2`
12. If you are using a virtual machine, the next steps are recommended for better usability but not required. If you are using a real machine, you
    can skip to step 18.
13. Remove the old kernel package: `sudo yum erase kernel`
14. To increase the screen resolution, edit /etc/default/grub and add `vga=0x347` to the `GRUB_CMDLINE_LINUX` line.  
    Then run `mkconfig-grub2 --output=/etc/grub2/grub.cfg` to push the changes to the boot menu.
15. Install the VirtualBox Guest additions as described in the [VirtualBox documentation](https://www.virtualbox.org/manual/ch04.html#idp96235792)
16. Reboot
17. Install the database and scripting packages: `sudo yum install mariadb mariadb-server mariadb-devel git python-pip python-matplotlib numpy
    python-devel MySQL-python lynx perl-DBI perl-DBD-MySQL perl-Test-Most perl-IO-String perl-DB_File perl-Capture-Tiny R htop`
18. Change to your home directory (`cd $HOME`) and download the NCBI BLAST and IgBLAST packages:  
 `curl -# ftp://ftp.ncbi.nih.gov/blast/executables/igblast/release/1.4.0/ncbi-igblast-1.4.0-1.x86_64.rpm --output ncbi-igblast-1.4.0-1.x86_64.rpm`   
 `curl -# ftp://ftp.ncbi.nih.gov/blast/executables/blast+/2.2.30/ncbi-blast-2.2.30+-3.x86_64.rpm --output ncbi-blast-2.2.30+-3.x86_64.rpm`   
    and install them using `yum install ncbi-*.rpm`.
19. Download and unzip RazerS3:  
    `curl -# http://packages.seqan.de/razers3/razers3-3.1.1-Linux-x86_64.tar.bz2 | tar -jx`
    then install the executable system-wide using: `sudo cp ./razers3-3.1.1-Linux-x86_64/bin/razers3 /usr/bin`
20. Download and unzip Muscle3:  
    `curl -# http://www.drive5.com/muscle/downloads3.8.31/muscle3.8.31_i86linux64.tar.gz | tar -zx`   
    then install the executable system-wide using: `sudo cp ./muscle3.8.31_i86linux64 /usr/bin; sudo ln -s /usr/bin/muscle3.8.31_i86linux64
    /usr/bin/muscle`.
21. Switch to a shell with full _root_ privileges: `sudo bash`;
24. Start `R`, then install `install.packages(RMySQL)`, `source("http://bioconductor.org/biocLite.R"); biocLite()` and `biocLite("flowCore")` and
    exit again using `q()`.
25. Prepare Bioperl installation, according to documentation on [bioperl.org](http://www.bioperl.org/wiki/Installing_BioPerl_on_Unix): First "Upgrade
    CPAN", then "Install/upgrade Module::Build".
26. Install packages, which are not present in the YUM repository: `cpan -i Data::Stag`
27. Install Bioperl: By calling `cpan` then `install CJFIELDS/BioPerl-1.6.924.tar.gz`
28. Leave _root_ shell via `exit`.
29. Enable database `sudo systemctl enable mariadb.service; sudo systemctl start mariadb.service`
30. Setup firewall allowing connections on tcp/22 (SSH) and tcp/3306 (MySQL)
31. /etc/ssh/sshd_config: Allow password-less login, prohibit root login
32. Setup port forwarding in VirtualBox, 60022 -> 22 and 63306 -> 3306
33. [host machine:] From the shell of the host machine, create an SSH tunnel for the subsequent database connection:  
    `ssh -fNL localhost:63310:localhost:3306 -p 60022 scireptor@localhost`
34. [host machine:] Use MySQL Workbench to connect to localhost:63310, then setup _root_ and _scireptor_ users in mariaDB. Make sure that user
    _scireptor_ has the necessary privileges to create database schemes when connecting from localhost. For convenience, _scireptor_ should
    also be allowed to connect to the database from the host machine (this saves you setting up the SSH tunnel everytime).


Installing and Running sciReptor
--------------------------------

###Preconfiguration
1.  Login as user _scireptor_, if necessary change to home directory (`cd $HOME`)
2.  Create MySQL configuration/authentication file: `echo -e -n "[mysql_igdb]\nuser=scireptor\n" >> $HOME/.my.cnf`
3.  Install public keys for datasets using: `curl -# http://b-cell-immunology.dkfz.de/public_keys.gpg.asc | gpg2 --import`

###Build Libraries
1.  Create and enter library directory: `mkdir sciReptor_test_library; cd sciReptor_test_library`
2.  Get current release: `git clone https://github.com/b-cell-immunology/sciReptor_library .`
3.  Build default sciReptor library: `./build_library_scireptor.sh`
4.  Build custom NCBIm38 mouse library: `./build_library_mouse_ncbim38.sh`
5.  Switch to home directory again: `cd ..`

###Run Test Data Set "Mouse B6"
1.  Create and enter project directory: `mkdir sciReptor_test_project_mouse; cd sciReptor_test_project_mouse`
2.  Create subdirectories: `mkdir bin raw_data quality_control pipeline_output`
3.  Get current sciReptor release: `git clone https://github.com/b-cell-immunology/sciReptor bin`
4.  Switch to code directory: `cd bin`
5.  Add version tag to config file, install config file in project root and edit it:  
    `echo -e -n "\nversion=$( git describe --tag --long --always )\n" >> config; mv config ..; vi ../config`
6.  Create database scheme  
    `mysql --defaults-file=$HOME/.my.cnf --defaults-group-suffix=_igdb -e "CREATE SCHEMA IF NOT EXISTS test_data_mouse_B6;"`   
    and its tables:  
    `mysql --defaults-file=$HOME/.my.cnf --defaults-group-suffix=_igdb --database=test_data_mouse_B6 < igdb_project.sql`
7.  Create run-specific directories using `make init-env run=test_data_mouse_B6`
8.  Switch to the data directory: `cd ../raw_data/test_data_mouse_B6`
9.  Download the test data set:  
    `curl -# http://b-cell-immunology.dkfz.de/sciReptor_datasets/test_data_mouse_B6.tar.bz2 --output test_data_mouse_B6.tar.bz2`   
    and test its integrity:  
    `sha256sum -c <( curl -# http://b-cell-immunology.dkfz.de/sciReptor_datasets/CHECKSUMS.sha256 | grep test_data_mouse_B6.tar.bz2 )`   
    Expected output is "test_data_mouse_B6.tar.bz2: OK"
10. Unpack and remove archive: `tar -jxf test_data_mouse_B6.tar.bz2; rm test_data_mouse_B6.tar.bz2` 
11. Verify the signature of the checksum list: `gpg2 --verify test_data_mouse_B6.sha256`  
    Expected output is "gpg: Good signature from 'XXX <XXX@dkfz-heidelberg.de>'"
12. Verify the integrity of the files: `sha256sum -c test_data_mouse_B6.sha256`  
    Expected output is "filename : OK" for each file
13. Switch back to code directory: `cd ../../bin`
14. Run sciReptor, substitute the number of availavailable CPU cores:  
    `./pipeline_start.sh --cores=<NUMBER_OF_CORES> --run=test_data_mouse_B6 --experiment_id=W02`

###Run Test Data Set "Human"
1.  Create and enter project directory: `mkdir sciReptor_test_project_human; cd sciReptor_test_project_human`
2.  Create subdirectories: `mkdir bin raw_data quality_control pipeline_output`
3.  Get current sciReptor release: `git clone https://github.com/b-cell-immunology/sciReptor bin`
4.  Switch to code directory: `cd bin`
5.  Add version tag to config file, install config file in project root and edit it:  
    `echo -e -n "\nversion=$( git describe --tag --long --always )\n" >> config; mv config ..; vi ../config`
6.  Create the database scheme  
    `mysql --defaults-file=$HOME/.my.cnf --defaults-group-suffix=_igdb -e "CREATE SCHEMA IF NOT EXISTS test_data_human;"`  
    and its tables  
    `mysql --defaults-file=$HOME/.my.cnf --defaults-group-suffix=_igdb --database=test_data_human < igdb_project.sql`
7.  Create run-specific directories using `make init-env run=test_data_human`
8.  Switch to the data directory: `cd ../raw_data/test_data_human`
9.  Download the test data set:  
    `curl -# http://b-cell-immunology.dkfz.de/sciReptor_datasets/test_data_human.tar.bz2 --output test_data_human.tar.bz2`   
    and test its integrity:  
    `sha256sum -c <( curl -# http://b-cell-immunology.dkfz.de/sciReptor_datasets/CHECKSUMS.sha256 | grep test_data_human.tar.bz2 )`   
    Expected output is "test_data_human.tar.bz2: OK"
10. Unpack and remove archive: `tar -jxf test_data_human.tar.bz2; rm test_data_human.tar.bz2`
11. Verify the signature of the checksum list: `gpg2 --verify test_data_human.sha256`  
    Expected output is "gpg: Good signature from 'XXX <XXX@dkfz-heidelberg.de>'"
12. Verify the integrity of the files: `sha256sum -c test_data_human.sha256`  
    Expected output is "filename : OK" for each file
13. Switch back to code directory: `cd ../../bin`
14. Run sciReptor, substitute the number of availavailable CPU cores:  
    `./pipeline_start.sh --cores=<NUMBER_OF_CORES> --run=test_data_human --experiment_id=D01`

###Run Test Data Set "Sanger"
1.  Create and enter project directory: `mkdir sciReptor_test_project_Sanger; cd sciReptor_test_project_Sanger`
2.  Create subdirectories: `mkdir bin raw_data quality_control pipeline_output`
3.  Get current sciReptor release: `git clone https://github.com/b-cell-immunology/sciReptor bin`
4.  Switch to code directory: `cd bin`
5.  Add version tag to config file, install config file in project root and edit it:  
    `echo -e -n "\nversion=$( git describe --tag --long --always )\n" >> config; mv config ..; vi ../config`
6.  Create the database scheme  
    `mysql --defaults-file=$HOME/.my.cnf --defaults-group-suffix=_igdb -e "CREATE SCHEMA IF NOT EXISTS test_data_Sanger;"`  
    and its tables  
    `mysql --defaults-file=$HOME/.my.cnf --defaults-group-suffix=_igdb --database=test_data_Sanger < igdb_project.sql`
7.  Create run-specific directories using `make -f Makefile.sanger init-env run=test_data_Sanger`
8.  Switch to the data directory: `cd ../raw_data/test_data_Sanger`
9.  Download the test data set:  
    `curl -# http://b-cell-immunology.dkfz.de/sciReptor_datasets/test_data_Sanger.tar.bz2 --output test_data_Sanger.tar.bz2`   
    and test its integrity:  
    `sha256sum -c <( curl -# http://b-cell-immunology.dkfz.de/sciReptor_datasets/CHECKSUMS.sha256 | grep test_data_Sanger.tar.bz2 )`   
    Expected output is "test_data_Sanger.tar.bz2: OK"
10. Unpack and remove archive: `tar -jxf test_data_Sanger.tar.bz2; rm test_data_Sanger.tar.bz2`
11. Verify the signature of the checksum list: `gpg2 --verify test_data_Sanger.sha256`  
    Expected output is "gpg: Good signature from 'XXX <XXX@dkfz-heidelberg.de>'"
12. Verify the integrity of the files: `sha256sum -c test_data_Sanger.sha256`  
    Expected output is "filename : OK" for each file
13. Switch back to code directory: `cd ../../bin`
14. Run sciReptor:  
    `make -f Makefile.sanger run=test_data_Sanger`
