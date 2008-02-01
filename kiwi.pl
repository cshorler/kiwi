#!/usr/bin/perl
#================
# FILE          : kiwi.pl
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : This is the main script to provide support
#               : for creating operating system images
#               : 
#               :
# STATUS        : $LastChangedBy: ms $
#               : $LastChangedRevision: 1 $
#----------------
use lib './modules';
use lib '/usr/share/kiwi/modules';
use strict;

#============================================
# perl debugger setup
#--------------------------------------------
$DB::inhibit_exit = 0;

#============================================
# Modules
#--------------------------------------------
use warnings;
use Getopt::Long;
use KIWIRoot;
use KIWIXML;
use KIWILog;
use KIWIImage;
use KIWIBoot;
use KIWIMigrate;
use KIWIOverlay;
use KIWIQX;

#============================================
# Globals (Version)
#--------------------------------------------
our $Version       = "2.18";
our $openSUSE      = "http://download.opensuse.org/repositories/";
our $ConfigFile    = "$ENV{'HOME'}/.kiwirc";
our $ConfigStatus  = 0;
#============================================
# Read $HOME/.kiwirc
#--------------------------------------------
if ( -f $ConfigFile) {
	my $kiwi = new KIWILog("tiny");
	if (! do $ConfigFile) {
		$kiwi -> warning ("Invalid $ConfigFile file...");
		$kiwi -> skipped ();
	} else {
		$kiwi -> info ("Using $ConfigFile");
		$kiwi -> done ();
		$ConfigStatus = 1;
	}
}
#============================================
# Globals
#--------------------------------------------
our $BasePath;         # configurable base kiwi path
our $System;           # configurable baes kiwi image desc. path
our $JabberServer;     # configurable jabber server
our $JabberPort;       # configurable jabber port
our $JabberUserName;   # configurable jabber user name
our $JabberPassword;   # configurable jabber password
our $JabberRessource;  # configurable jabber ressource
our $JabberComponent;  # configurable jabber component
our $LogServerPort;    # configurable log server port
our $Gzip;             # configurable gzip command
if (! defined $LogServerPort) {
	$LogServerPort = 9000;
}
if (! defined $Gzip) {
	$Gzip = "gzip -9";
}
if (! defined $JabberPort) {
	$JabberPort = 5223;
}
if ( ! defined $BasePath ) {
	$BasePath = "/usr/share/kiwi";
}
if ( ! defined $System ) {
	$System  = $BasePath."/image";
}
our $Tools   = $BasePath."/tools";
our $Scheme  = $BasePath."/modules/KIWIScheme.rng";
our $KConfig = $BasePath."/modules/KIWIConfig.sh";
our $KMigrate= $BasePath."/modules/KIWIMigrate.txt";
our $Revision= $BasePath."/.revision";

#============================================
# Globals
#--------------------------------------------
our $Prepare;           # control XML file for building chroot extend
our $Create;            # image description for building image extend
our $CreateInstSource;  # create installation source from meta packages
our $Upgrade;           # upgrade physical extend
our $Destination;       # destination directory for logical extends
our $LogFile;           # optional file name for logging
our $RootTree;          # optional root tree destination
our $Survive;           # if set to "yes" don't exit kiwi
our $BootStick;         # deploy initrd booting from USB stick
our $BootStickSystem;   # system image to be copied on an USB stick
our $BootStickDevice;   # device to install stick image on
our $BootVMSystem;      # system image to be copied on a VM disk
our $BootVMFormat;      # virtual disk format supported by qemu-img
our $BootVMDisk;        # deploy initrd booting from a VM 
our $BootVMSize;        # size of virtual disk
our $InstallCD;         # Installation initrd booting from CD
our $InstallCDSystem;   # virtual disk system image to be installed on disk
our $BootCD;            # Boot initrd booting from CD
our $InstallStick;      # Installation initrd booting from USB stick
our $InstallStickSystem;# virtual disk system image to be installed on disk
our $StripImage;        # strip shared objects and binaries
our $CreatePassword;    # create crypt password string
our $CreateHash;        # create .checksum.md5 for given description
our $SetupSplashForGrub;# setup splash screen(s) for grub
our $ImageName;         # filename of current image, used in Modules
our %ForeignRepo;       # may contain XML::LibXML::Element objects
our @AddRepository;     # add repository for building physical extend
our @AddRepositoryType; # add repository type
our @AddPackage;        # add packages to the image package list
our $IgnoreRepos;       # ignore repositories specified so far
our $SetRepository;     # set first repository for building physical extend
our $SetRepositoryType; # set firt repository type
our $SetImageType;      # set image type to use, default is primary type
our $Migrate;           # migrate running system to image description
our @Exclude;           # exclude directories in migrate search
our $Report;            # create report on root/ tree migration only
our @Profiles;          # list of profiles to include in image
our $ListProfiles;      # lists the available profiles in image
our $ForceNewRoot;      # force creation of new root directory
our $BaseRoot;          # use given path as base system
our $BaseRootMode;      # specify base-root mode copy | union
our $NoColor;           # do not used colored output (done/failed messages)
our $LogPort;           # specify alternative log server port
our $GzipCmd;           # command to run to gzip things
our $PrebuiltBootImage; # directory where a prepared boot image may be found
our $PreChrootCall;     # program name called before chroot switch
our $listXMLInfo;       # list XML information for this operation
our $Compress;          # set compression level
our $kiwi;              # global logging handler object

#============================================
# Globals
#--------------------------------------------
my $root;       # KIWIRoot  object for installations
my $image;      # KIWIImage object for logical extends
my $boot;       # KIWIBoot  object for logical extends
my $migrate;    # KIWIMigrate object for system to image migration

#==========================================
# main
#------------------------------------------
sub main {
	# ...
	# This is the KIWI project to prepare and build operating
	# system images from a given installation source. The system
	# will create a chroot environment representing the needs
	# of a XML control file. Once prepared KIWI can create several
	# OS image types.
	# ---
	#==========================================
	# Initialize and check options
	#------------------------------------------
	init();
	#==========================================
	# Create logger object
	#------------------------------------------
	if (! defined $kiwi) {
		$kiwi = new KIWILog();
	}
	#==========================================
	# Check for nocolor option
	#------------------------------------------
	if (defined $NoColor) {
		$kiwi -> info ("Switching off colored output\n");
		if (! $kiwi -> setColorOff ()) {
			my $code = kiwiExit (1); return $code;
		}
	}
	#==========================================
	# Setup logging location
	#------------------------------------------
	if (defined $LogFile) {
		if ((! defined $Survive) || ($Survive ne "yes")) {
			$kiwi -> info ("Setting log file to: $LogFile\n");
			if (! $kiwi -> setLogFile ( $LogFile )) {
				my $code = kiwiExit (1); return $code;
			}
		}
	}
	#========================================
	# Create instsource from meta packages
	#----------------------------------------
	if (defined $CreateInstSource) {
		$kiwi -> info ("Reading image description...");
		my $xml = new KIWIXML ( $kiwi,$CreateInstSource );
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		$kiwi -> done();
		#==========================================
		# Initialize installation source tree
		#------------------------------------------
		my @root = $xml -> createTmpDirectory ( $RootTree );
		my $root = $root[1];
		if (! defined $root) {
			$kiwi -> error ("Couldn't create instsource root");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		# TODO
		# test code only...
		print "*** DIR = $root\n";
		my %source = $xml -> getInstSourceRepository();
		my @slist  = keys %source;
		print "*** SOURCE = @slist\n";
		my @arch = $xml -> getInstSourceArchList();
		print "*** ARCH(S): @arch\n";
		my %metapacks = $xml -> getInstSourceMetaPackageList();
		my %metafiles = $xml -> getInstSourceMetaFiles();
		my %pack = $xml -> getInstSourcePackageList();
		foreach (keys %metapacks) {
			my $p = $_;
			my $a = $metapacks{$p};
			print "$p -> ";
			if (defined $a) {
				print "$a\n";
			} else {
				print "undefined\n";
			}
		}
		foreach (keys %metafiles) {
			print "URL: $_\n";
		}
		my $surl=$source{other_repo}{source};
		my $file="$surl/kiwi-desc-usbboot.*\.rpm";
		if (! $xml->getInstSourceFile ($file,$root)) {
			$kiwi -> error ("Couldn't download file");
			$kiwi -> failed ();
		}
		# TODO
		# Hi Jan, this is your playground :-) Have fun
		# ...
		kiwiExit (0);
	}

	#========================================
	# Prepare image and build chroot system
	#----------------------------------------
	if (defined $Prepare) {
		$kiwi -> info ("Reading image description...");
		my $xml = new KIWIXML ( $kiwi,$Prepare,\%ForeignRepo,undef,\@Profiles );
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		$kiwi -> done();
		if (! $xml -> haveMD5File()) {
			$kiwi -> warning ("Description provides no MD5 hash, check");
			$kiwi -> skipped ();
		}
		#==========================================
		# Check for bootprofile in config.xml
		#------------------------------------------
		if (! @Profiles) {
			my %type = %{$xml->getImageTypeAndAttributes()};
			if (($type{"type"} eq "cpio") && ($type{bootprofile})) {
				@Profiles = split (/,/,$type{bootprofile});
				if (! $xml -> checkProfiles (\@Profiles)) {
					my $code = kiwiExit (1); return $code;
				}
			}
		}
		#==========================================
		# Check for default root in XML
		#------------------------------------------	
		if (! defined $RootTree) {
			$kiwi -> info ("Checking for default root in XML data...");
			$RootTree = $xml -> getImageDefaultRoot();
			if ($RootTree) {
				if ($RootTree !~ /^\//) {
					my $workingDir = qxx ( "pwd" ); chomp $workingDir;
					$RootTree = $workingDir."/".$RootTree;
				}
				$kiwi -> done();
			} else {
				undef $RootTree;
				$kiwi -> notset();
			}
		}
		#==========================================
		# Check for default base root in XML
		#------------------------------------------
		if (! defined $BaseRoot) {
			$kiwi -> info ("Checking for default baseroot in XML data...");
			$BaseRoot = $xml -> getImageDefaultBaseRoot();
			if ($BaseRoot) {
				$kiwi -> done();
			} else {
				undef $BaseRoot;
				$kiwi -> notset();
			}
		}
		#==========================================
		# Check for ignore-repos option
		#------------------------------------------
		if (defined $IgnoreRepos) {
			$xml -> ignoreRepositories ();
		}
		#==========================================
		# Check for set-repo option
		#------------------------------------------
		if (defined $SetRepository) {
			$xml -> setRepository ($SetRepositoryType,$SetRepository);
		}
		#==========================================
		# Check for add-repo option
		#------------------------------------------
		if (defined @AddRepository) {
			$xml -> addRepository (\@AddRepositoryType,\@AddRepository);
		}
		#==========================================
		# Validate repo types
		#------------------------------------------
		$xml -> setValidateRepositoryType();
		#==========================================
		# Check for add-package option
		#------------------------------------------
		if (defined @AddPackage) {
			$xml -> addImagePackages (@AddPackage);
		}
		#==========================================
		# Check for inheritance
		#------------------------------------------
		if (! $xml -> setupImageInheritance()) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Initialize root system
		#------------------------------------------
		$root = new KIWIRoot (
			$kiwi,$xml,$Prepare,$RootTree,
			"/base-system",undef,undef,$BaseRoot,$BaseRootMode
		);
		if (! defined $root) {
			$kiwi -> error ("Couldn't create root object");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		if (! defined $BaseRoot) {
			if (! defined $root -> init ()) {
				$kiwi -> error ("Base initialization failed");
				$kiwi -> failed ();
				my $code = kiwiExit (1); return $code;
			}
		}
		#==========================================
		# Check for pre chroot call
		#------------------------------------------
		if (defined $PreChrootCall) {
			$kiwi -> info ("Calling pre-chroot program: $PreChrootCall");
			my $path = $root -> getRootPath();
			my $data = qxx ("$PreChrootCall $path 2>&1");
			my $code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> info   ($data);
				$kiwi -> failed ();
				my $code = kiwiExit (1); return $code;
			} else {
				$kiwi -> loginfo ("$PreChrootCall: $data");
			}
			$kiwi -> done ();
		}
		#==========================================
		# Install root system
		#------------------------------------------
		if (! $root -> install ()) {
			$kiwi -> error ("Image installation failed");
			$kiwi -> failed ();
			$root -> cleanMount ();
			my $code = kiwiExit (1); return $code;
		}
		if (! $root -> setup ()) {
			$kiwi -> error ("Couldn't setup image system");
			$kiwi -> failed ();
			$root -> cleanMount ();
			my $code = kiwiExit (1); return $code;
		}
		$root -> cleanMount ();
		kiwiExit (0);
	}

	#==========================================
	# Create image from chroot system
	#------------------------------------------
	if (defined $Create) {
		#==========================================
		# Check for overlay requirements
		#------------------------------------------
		my $overlay;
		my $origroot;
		if (defined $BaseRoot) {
			if ((defined $BaseRootMode) && ($BaseRootMode eq "union")) {
				$overlay = new KIWIOverlay ( $kiwi,$BaseRoot,$Create );
				if (! defined $overlay) {
					my $code = kiwiExit (1); return $code;
				}
				if (defined $BaseRootMode) {
					$overlay -> setMode ($BaseRootMode);
				}
				$origroot = $Create;
				$Create = $overlay -> mountOverlay();
				if (! defined $Create) {
					my $code = kiwiExit (1); return $code;
				}
			}
		}
		$kiwi -> info ("Reading image description...");
		my $xml = new KIWIXML ( $kiwi,"$Create/image",undef,$SetImageType );
		if (! defined $xml) {
			if (defined $BaseRoot) {
				$overlay -> resetOverlay();
			}
			my $code = kiwiExit (1); return $code;
		}
		$kiwi -> done();
		#==========================================
		# Check for default destination in XML
		#------------------------------------------
		if (! defined $Destination) {
			$kiwi -> info ("Checking for defaultdestination in XML data...");
			$Destination = $xml -> getImageDefaultDestination();
			if (! $Destination) {
				$kiwi -> failed ();
				$kiwi -> info   ("No destination directory specified");
				$kiwi -> failed ();
				if (defined $BaseRoot) {
					$overlay -> resetOverlay();
				}
				my $code = kiwiExit (1); return $code;
			}
			$kiwi -> done();
		}
		#==========================================
		# Check for default base root in XML
		#------------------------------------------
		if (! defined $BaseRoot) {
			$kiwi -> info ("Checking for default baseroot in XML data...");
			$BaseRoot = $xml -> getImageDefaultBaseRoot();
			if ($BaseRoot) {
				$kiwi -> done();
			} else {
				undef $BaseRoot;
				$kiwi -> notset();
			}
        }
		#==========================================
		# Check for --compress option
		#------------------------------------------
		if (defined $Compress) {
			$kiwi -> info ("Set compression level to: $Compress");
			$xml  -> setCompressed ($Compress);
			$kiwi -> done();
		}
		#==========================================
		# Check type params and create image obj
		#------------------------------------------
		$image = new KIWIImage (
			$kiwi,$xml,$Create,$Destination,$StripImage,
			"/base-system",$origroot
		);
		if (! defined $image) {
			if (defined $BaseRoot) {
				$overlay -> resetOverlay();
			}
			my $code = kiwiExit (1); return $code;
		}
		my %type = %{$xml->getImageTypeAndAttributes()};
		my $para = checkType ( \%type );
		if (! defined $para) {
			if (defined $BaseRoot) {
				$overlay -> resetOverlay();
			}
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Check for type packages if any
		#------------------------------------------
		my @addonList;
		if ($type{type} eq "vmx") {
			$kiwi -> info ("Creating VMware package list");
			@addonList = $xml -> getVMwareList();
			$kiwi -> done();
		}
		if ($type{type} eq "xen") {
			$kiwi -> info ("Creating Xen package list");
			@addonList = $xml -> getXenList();
			$kiwi -> done();
		}
		if (@addonList) {
			$kiwi -> info ("Installing packages: @addonList...\n");
			$kiwi -> warning (
				"*** Packages installed here won't be removed later ***\n"
			);
			$main::Survive = "yes";
			$main::Upgrade = $Create;
			@main::AddPackage = @addonList;
			undef $main::Create;
			if (! defined main::main()) {
				$main::Survive = "default";
				if (defined $BaseRoot) {
					$overlay -> resetOverlay();
				}
				my $code = kiwiExit (1); return $code;
			}
			$main::Survive = "default";
			$main::Create  = $main::Upgrade;
			undef $main::Upgrade;
		}
		#==========================================
		# Initialize logical image extend
		#------------------------------------------
		my $ok;
		SWITCH: for ($type{type}) {
			/^ext2/     && do {
				$ok = $image -> createImageEXT2 ();
				last SWITCH;
			};
			/^ext3/     && do {
				$ok = $image -> createImageEXT3 ();
				last SWITCH;
			};
			/^reiserfs/ && do {
				$ok = $image -> createImageReiserFS ();
				last SWITCH;
			};
			/^squashfs/ && do {
				$ok = $image -> createImageSquashFS ();
				last SWITCH;
			};
			/^cpio/     && do {
				$ok = $image -> createImageCPIO ();
				last SWITCH;
			};
			/^iso/      && do {
				$ok = $image -> createImageLiveCD ( $para );
				last SWITCH;
			};
			/^split/    && do {
				$ok = $image -> createImageSplit ( $para );
				last SWITCH;
			};
			/^usb/      && do {
				$ok = $image -> createImageUSB ( $para );
				last SWITCH;
			};
			/^vmx/      && do {
				$ok = $image -> createImageVMX ( $para );
				last SWITCH;
			};
			/^oem/      && do {
				$ok = $image -> createImageVMX ( $para );
				last SWITCH;
			};
			/^xen/      && do {
				$ok = $image -> createImageXen ( $para );
				last SWITCH;
			};
			/^pxe/      && do {
				$ok = $image -> createImagePXE ( $para );
				last SWITCH;
			};
			$kiwi -> error  ("Unsupported type: $type{type}");
			$kiwi -> failed ();
			if (defined $BaseRoot) {
				$overlay -> resetOverlay();
			}
			my $code = kiwiExit (1); return $code;
		}
		if (defined $BaseRoot) {
			$overlay -> resetOverlay();
		}
		if ($ok) {
			my $code = kiwiExit (0); return $code;
		} else {
			my $code = kiwiExit (1); return $code;
		}
	}

	#==========================================
	# Upgrade image in chroot system
	#------------------------------------------
	if (defined $Upgrade) {
		$kiwi -> info ("Reading image description...");
		my $xml = new KIWIXML ( $kiwi,"$Upgrade/image" );
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		$kiwi -> done();
		#==========================================
		# Check for default base root in XML
		#------------------------------------------
		if (! defined $BaseRoot) {
			$kiwi -> info ("Checking for default baseroot in XML data...");
			$BaseRoot = $xml -> getImageDefaultBaseRoot();
			if ($BaseRoot) {
				$kiwi -> done();
			} else {
				undef $BaseRoot;
				$kiwi -> notset();
			}
		}
		#==========================================
		# Check for ignore-repos option
		#------------------------------------------
		if (defined $IgnoreRepos) {
			$xml -> ignoreRepositories ();
		}
		#==========================================
		# Check for set-repo option
		#------------------------------------------
		if (defined $SetRepository) {
			$xml -> setRepository ($SetRepositoryType,$SetRepository);
		}
		#==========================================
		# Check for add-repo option
		#------------------------------------------
		if (defined @AddRepository) {
			$xml -> addRepository (\@AddRepositoryType,\@AddRepository);
		}
		#==========================================
		# Validate repo types
		#------------------------------------------
		$xml -> setValidateRepositoryType();
		#==========================================
		# Initialize root system, use existing root
		#------------------------------------------
		$root = new KIWIRoot (
			$kiwi,$xml,$Upgrade,undef,
			"/base-system",$Upgrade,\@AddPackage,$BaseRoot,$BaseRootMode
		);
		if (! defined $root) {
			$kiwi -> error ("Couldn't create root object");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Upgrade root system
		#------------------------------------------
		if (! $root -> upgrade ()) {
			$kiwi -> error ("Image Upgrade failed");
			$kiwi -> failed ();
			$root -> cleanMount ();
			my $code = kiwiExit (1); return $code;
		}
		$root -> cleanMount ();
		kiwiExit (0);
	}

	#==========================================
	# Migrate systm to image description
	#------------------------------------------
	if (defined $Migrate) {
		$kiwi -> info ("Starting system to image migration");
		$migrate = new KIWIMigrate (
			$kiwi,$Destination,$Migrate,\@Exclude,$Report
		);
		if (! defined $migrate) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $migrate -> setTemplate()) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $migrate -> setServiceList()) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $migrate -> setSystemConfiguration()) {
			my $code = kiwiExit (1); return $code;
		}
		kiwiExit (0);
	}

	#==========================================
	# Create a crypted password and print it
	#------------------------------------------
	if (defined $CreatePassword) {
		my $word2 = 2;
		my $word1 = 1;
		my $salt  = (getpwuid ($<))[1];
		while ($word1 ne $word2) {
			$kiwi -> info ("Enter Password: ");
			system "stty -echo";
			chomp ($word1 = <STDIN>);
			system "stty echo";
			$kiwi -> done ();
			$kiwi -> info ("Reenter Password: ");
			system "stty -echo";
			chomp ($word2 = <STDIN>);
			system "stty echo";
			if ( $word1 ne $word2 ) {
				$kiwi -> failed ();
				$kiwi -> info ("*** Passwords differ, please try again ***");
				$kiwi -> failed ();
			}
		}
		$kiwi -> done ();
		my $pwd = crypt ($word1, $salt);
		$kiwi -> info ("Your password:\n\t$pwd\n");
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create md5 hash for given description
	#------------------------------------------
	if (defined $CreateHash) {
		$kiwi -> info ("Creating MD5 sum for $CreateHash...");
		if (! -d $CreateHash) {
			$kiwi -> failed ();
			$kiwi -> error  ("Not a directory: $CreateHash: $!");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		if (! -f "$CreateHash/config.xml") {
			$kiwi -> failed ();
			$kiwi -> error  ("Not a kiwi description: no config.xml found");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		my $cmd  = "find -L -type f";
		my $status = qxx ("cd $CreateHash&&$cmd|xargs md5sum > .checksum.md5");
		my $result = $? >> 8;
		if ($result != 0) {
			$kiwi -> error  ("Failed creating md5 sum: $status: $!");
			$kiwi -> failed ();
		}
		$kiwi -> done();
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# setup a splash initrd
	#------------------------------------------
	if (defined $SetupSplashForGrub) {
		$boot = new KIWIBoot ($kiwi,$SetupSplashForGrub);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		$boot -> setupSplashForGrub();
		$boot -> cleanTmp();
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Write a initrd/system image to USB stick
	#------------------------------------------
	if (defined $BootStick) {
		$kiwi -> info ("Creating boot USB stick from: $BootStick...\n");
		$boot = new KIWIBoot (
			$kiwi,$BootStick,$BootStickSystem,undef,
			$BootStickDevice
		);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupBootStick()) {
			$boot -> cleanTmp();
			my $code = kiwiExit (1); return $code;
		}
		$boot -> cleanTmp();
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create a boot CD (ISO)
	#------------------------------------------
	if (defined $BootCD) {
		$kiwi -> info ("Creating boot ISO from: $BootCD...\n");
		$boot = new KIWIBoot ($kiwi,$BootCD);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallCD()) {
			my $code = kiwiExit (1); return $code;
		}
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create an install CD (ISO)
	#------------------------------------------
	if (defined $InstallCD) {
		$kiwi -> info ("Creating install ISO from: $InstallCD...\n");
		if (! defined $InstallCDSystem) {
			$kiwi -> error  ("No Install system image specified");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		$boot = new KIWIBoot ($kiwi,$InstallCD,$InstallCDSystem);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallCD()) {
			$boot -> cleanTmp();
			my $code = kiwiExit (1); return $code;
		}
		$boot -> cleanTmp();
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create an install USB stick
	#------------------------------------------
	if (defined $InstallStick) {
		$kiwi -> info ("Creating install Stick from: $InstallStick...\n");
		if (! defined $InstallStickSystem) {
			$kiwi -> error  ("No Install system image specified");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		$boot = new KIWIBoot ($kiwi,$InstallStick,$InstallStickSystem);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallStick()) {
			$boot -> cleanTmp();
			my $code = kiwiExit (1); return $code;
		}
		$boot -> cleanTmp();
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create a virtual disk image
	#------------------------------------------
	if (defined $BootVMDisk) {
		$kiwi -> info ("Creating boot VM disk from: $BootVMDisk...\n");
		if (! defined $BootVMSystem) {
			$kiwi -> error  ("No VM system image specified");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		qxx ( "file $BootVMSystem | grep -q 'gzip compressed data'" );
		my $code = $? >> 8;
		if ($code == 0) {
			$kiwi -> failed ();
			$kiwi -> error  ("Can't use compressed VM system");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		$boot = new KIWIBoot (
			$kiwi,$BootVMDisk,$BootVMSystem,
			$BootVMSize,undef,$BootVMFormat
		);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupBootDisk()) {
			$boot -> cleanTmp();
			my $code = kiwiExit (1); return $code;
		}
		$boot -> cleanTmp();
		$code = kiwiExit (0); return $code;
	}
	return 1;
}

#==========================================
# init
#------------------------------------------
sub init {
	# ...
	# initialize, check privilege and options. KIWI
	# requires you to perform at least one action.
	# An action is either to prepare or create an image
	# ---
	$SIG{"HUP"}      = \&quit;
	$SIG{"TERM"}     = \&quit;
	$SIG{"INT"}      = \&quit;
	my $kiwi = new KIWILog("tiny");
	my $result = GetOptions(
		"version"               => \&version,
		"logfile=s"             => \$LogFile,
		"prepare|p=s"           => \$Prepare,
		"add-profile=s"         => \@Profiles,
		"migrate|m=s"           => \$Migrate,
		"exclude|e=s"           => \@Exclude,
		"report"                => \$Report,
		"list|l"                => \&listImage,
		"create|c=s"            => \$Create,
		"create-instsource=s"   => \$CreateInstSource,
		"ignore-repos"          => \$IgnoreRepos,
		"add-repo=s"            => \@AddRepository,
		"add-repotype=s"        => \@AddRepositoryType,
		"add-package=s"         => \@AddPackage,
		"set-repo=s"            => \$SetRepository,
		"set-repotype=s"        => \$SetRepositoryType,
		"type|t=s"              => \$SetImageType,
		"upgrade|u=s"           => \$Upgrade,
		"destdir|d=s"           => \$Destination,
		"root|r=s"              => \$RootTree,
		"bootstick=s"           => \$BootStick,
		"bootvm=s"              => \$BootVMDisk,
		"bootstick-system=s"    => \$BootStickSystem,
		"bootstick-device=s"    => \$BootStickDevice,
		"bootvm-system=s"       => \$BootVMSystem,
		"bootvm-format=s"       => \$BootVMFormat,
		"bootvm-disksize=s"     => \$BootVMSize,
		"installcd=s"           => \$InstallCD,
		"installcd-system=s"    => \$InstallCDSystem,
		"bootcd=s"              => \$BootCD,
		"installstick=s"        => \$InstallStick,
		"installstick-system=s" => \$InstallStickSystem,
		"strip|s"               => \$StripImage,
		"createpassword"        => \$CreatePassword,
		"createhash=s"          => \$CreateHash,
		"setup-grub-splash=s"   => \$SetupSplashForGrub,
		"list-profiles|i=s"     => \$ListProfiles,
		"force-new-root"        => \$ForceNewRoot,
		"base-root=s"           => \$BaseRoot,
		"base-root-mode=s"      => \$BaseRootMode,
		"nocolor"               => \$NoColor,
		"log-port=i"            => \$LogPort,
		"gzip-cmd=s"            => \$GzipCmd,
		"prebuiltbootimage=s"   => \$PrebuiltBootImage,
		"prechroot-call=s"      => \$PreChrootCall,
		"listxmlinfo|x=s"       => \$listXMLInfo,
		"compress=s"            => \$Compress,
		"help|h"                => \&usage,
		"<>"                    => \&usage
	);
	my $user = qxx ("whoami");
	if ($user !~ /root/i) {
		$kiwi -> error ("Only root can do this");
		$kiwi -> failed ();
		usage();
	}
	if ( $result != 1 ) {
		usage();
	}
	if (
		(! defined $Prepare) && (! defined $Create) &&
		(! defined $BootStick) && (! defined $InstallCD) &&
		(! defined $Upgrade) && (! defined $SetupSplashForGrub) &&
		(! defined $BootVMDisk) && (! defined $CreatePassword) &&
		(! defined $CreateInstSource) && (! defined $Migrate) &&
		(! defined $ListProfiles) && (! defined $InstallStick) &&
		(! defined $listXMLInfo) && (! defined $BootCD) &&
		(! defined $CreateHash)
	) {
		$kiwi -> error ("No operation specified");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $IgnoreRepos) && (defined $SetRepository)) {
		$kiwi -> error ("Can't use ignore repos together with set repos");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined @AddRepository) && (! defined @AddRepositoryType)) {
		$kiwi -> error ("No repository type specified");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $RootTree) && ($RootTree !~ /^\//)) {
		my $workingDir = qxx ( "pwd" ); chomp $workingDir;
		$RootTree = $workingDir."/".$RootTree;
	}
	if ((defined $Migrate) && (! defined $Destination)) {
		$kiwi -> error ("No migration destination directory specified");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if (defined $LogPort) {
		$kiwi -> info ("Setting log server port to: $LogPort");
		$LogServerPort = $LogPort;
		$kiwi -> done ();
	}
	if (defined $GzipCmd) {
		$kiwi -> info ("Setting gzip command to: $GzipCmd");
		$Gzip = $GzipCmd;
		$kiwi -> done ();
	}
	if ((defined $BaseRootMode) && (! defined $BaseRoot)) {
		$kiwi -> error ("base root mode specified but no base root tree");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;   
	}
	if ((defined $BaseRootMode) &&
		($BaseRootMode !~ /^copy$|^union$|^recycle$/)
	) {
		$kiwi -> error ("Invalid baseroot mode,allowed are copy|union|recycle");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $BaseRootMode) && ($BaseRootMode eq "recycle")) {
		if (defined $RootTree) {
			$kiwi -> warning ("--root ignored in recycle base root mode !");
			$kiwi -> skipped ();
		}
		$RootTree = $BaseRoot;
	}
	if ((defined $Compress) && ($Compress !~ /^yes$|^no$/)) {
		$kiwi -> error ("Invalid compress argument, expected yes|no");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $PreChrootCall) && (! -x $PreChrootCall)) {
		$kiwi -> error ("pre-chroot program: $PreChrootCall");
		$kiwi -> failed ();
		$kiwi -> error ("--> 1) no such file or directory\n");
		$kiwi -> error ("--> 2) and/or not in executable format\n");
		my $code = kiwiExit (1); return $code;
	}
	#==========================================
	# remove pre-defined smart channels
	#------------------------------------------
	qxx ( "rm -f /etc/smart/channels/*" );
	#==========================================
	# Handle ListProfiles option
	#------------------------------------------
	if (defined $ListProfiles) {
		listProfiles();
	}
	#==========================================
	# Handle listXMLInfo option
	#------------------------------------------
	if (defined $listXMLInfo) {
		listXMLInfo();
	}
}

#==========================================
# usage
#------------------------------------------
sub usage {
	# ...
	# Explain the available options for this
	# image creation system
	# ---
	my $kiwi = new KIWILog("tiny");
	my $date = qxx ( "LANG=POSIX date -I" ); chomp $date;
	print "Linux KIWI setup  (image builder) ($date)\n";
	print "Copyright (c) 2007 - SUSE LINUX Products GmbH\n";
	print "\n";

	print "Usage:\n";
	print "  kiwi -l | --list\n";
	print "  kiwi -i | --list-profiles <image-path>\n";
	print "  kiwi -x | --listxmlinfo <image-path> [--type <image-type>]\n";
	print "Image Preparation/Creation:\n";
	print "  kiwi -p | --prepare <image-path>\n";
	print "     [ --base-root <base-path> ]\n";
	print "     [ --base-root-mode <copy|union|recycle> ]\n";
	print "     [ --add-profile <profile-name> ]\n";
	print "  kiwi -c | --create  <image-root>\n";
	print "     [ --base-root <base-path> ]\n";
	print "     [ --base-root-mode <copy|union|recycle> ]\n";
	print "     [ --prebuiltbootimage <directory>]\n";
	print "Image Upgrade:\n";
	print "  kiwi -u | --upgrade <image-root>\n";
	print "     [ --base-root <base-path> ]\n";
	print "System to Image migration:\n";
	print "  kiwi -m | --migrate <name> --destdir <destination-path>\n";
	print "     [ --exclude <directory> --exclude ... ]\n";
	print "     [ --report ]\n";
	print "Image postprocessing modes:\n";
	print "  kiwi --bootstick <initrd>\n";
	print "     [ --bootstick-system <systemImage> ]\n";
	print "     [ --bootstick-device <device> ]\n";
	print "  kiwi --bootvm <initrd> --bootvm-system <systemImage>\n";
	print "     [ --bootvm-disksize <size> ]\n";
	print "     [ --bootvm-format <format> ]\n";
	print "  kiwi --bootcd <initrd>\n";
	print "  kiwi --installcd <initrd>\n";
	print "       --installcd-system <vmx-system-image>\n";
	print "  kiwi --installstick <initrd>\n";
	print "       --installstick-system <vmx-system-image>\n";
	print "Helper Tools:\n";
	print "  kiwi --createpassword\n";
	print "  kiwi --createhash <image-path>\n";
	print "  kiwi --create-instsource <image-path>\n";
	print "  kiwi --setup-grub-splash <initrd>\n";
	print "Options:\n";
	print "--\n";
	print "  [ -d | --destdir <destination-path> ]\n";
	print "    Specify destination directory to store the image file(s)\n";
	print "    If not specified the the attribute <defaultdestination>\n";
	print "    is used. If no destination can be found an error occurs\n";
	print "\n";
	print "  [ -t | --type <image-type> ]\n";
	print "    Specify the output image type to use for this image\n";
	print "    The type must exist in the config.xml description\n";
	print "    By the default the primary type will be used. If there is\n";
	print "    no primary attribute set the first type entry of the\n";
	print "    preferences section is the primary type\n"; 
	print "    makes only sense in combination with --create\n";
	print "\n";
	print "  [ -r | --root <root-path> ]\n";
	print "    Setup the physical extend, chroot system below the\n";
	print "    given root-path path. If no --root option is given kiwi\n";
	print "    will search for the attribute defaultroot in config.xml\n";
	print "    If no root directory is known a mktmp directory\n";
	print "    will be created and used as root directory\n";
	print "\n";
	print "  [ -s | --strip ]\n";
	print "    Strip shared objects and executables\n";
	print "    makes only sense in combination with --create\n";
	print "\n";
	print "  [ --add-repo <repo-path> --add-repotype <type> ]\n";
	print "    Add the given repository and type for this run of an\n";
	print "    image prepare or upgrade process.\n";
	print "    Multiple --add-repo/--add-repotype options are possible\n";
	print "    The change will not be written to the config.xml file\n";
	print "\n";
	print "  [ --ignore-repos ]\n";
	print "    Ignore all repositories specified so-far, in XML or\n";
	print "    otherwise.  This option should be used in conjunction\n";
	print "    with subsequent calls to --add-repo to specify\n";
	print "    repositories at the command-line that override previous\n";
	print "    specifications.\n";
	print "\n";
	print "  [ --set-repo <repo-path> [ --set-repotype <type> ]]\n";
	print "    set the given repository and optional type for the first\n";
	print "    repository entry within the config.xml. The change will not\n";
	print "    be written to the xml file and is valid for this run of\n";
	print "    image prepare or upgrade process.\n";
	print "\n";
	print "  [ --add-package <package> ]\n";
	print "    Add the given package name to the list of image packages\n";
	print "    multiple --add-package options are possible. The change\n";
	print "    will not be written to the config.xml file\n";
	print "\n";
	print "  [ --logfile <filename> | terminal ]\n";
	print "    Write to the log file \`<filename>' instead of\n";
	print "    the terminal.\n";
	print "\n";
	print "  [ --gzip-cmd <cmd> ]\n";
	print "    Specify an alternate command to run when compressing boot\n";
	print "    and system images.  Command must accept gzip options.\n";
	print "\n";
	print "  [ --force-new-root ]\n";
	print "    Force creation of new root directory. If the directory\n";
	print "    already exists, it is deleted.\n";
	print "\n";
	print "  [ --log-port <port-number> ]\n";
	print "    Set the log server port. By default port 9000 is used\n";
	print "    If multiple kiwi processes runs on one system it's\n";
	print "    recommended to set the logging port per process\n";
	print "\n";
	print "  [ --prebuiltbootimage <directory> ]\n";
	print "    search in <directory> for pre-built boot images\n";
	print "--\n";
	version();
}

#==========================================
# listImage
#------------------------------------------
sub listImage {
	# ...
	# list known image descriptions and exit
	# ---
	my $kiwi = new KIWILog("tiny");
	opendir (FD,$System);
	my @images = readdir (FD); closedir (FD);
	foreach my $image (@images) {
		if ($image =~ /^\./) {
			next;
		}
		if (-l "$System/$image") {
			next;
		}
		if (-f "$System/$image/config.xml") {
			$kiwi -> info ("$image");
			my $xml = new KIWIXML ( $kiwi,"$System/$image" );
			if (! $xml) {
				$kiwi -> failed();
				next;
			}
			my $version = $xml -> getImageVersion();
			$kiwi -> note (" -> Version: $version");
			$kiwi -> done();
		}
	}
	exit 0;
}

#==========================================
# listProfiles
#------------------------------------------
sub listProfiles {
	# ...
	# list the available profiles in image
	# ---
	my $kiwi = new KIWILog("tiny");
	my $xml  = new KIWIXML ($kiwi, $ListProfiles);
	if (! defined $xml) {
		$kiwi -> failed();
		exit 1;
	}
	my @profiles = $xml -> getProfiles ();
	if ((scalar @profiles) == 0) {
		$kiwi -> info ("No profiles available");
		$kiwi -> done ();
		exit 0;
	}
	foreach my $profile (@profiles) {
		my $name = $profile -> {name};
		my $desc = $profile -> {description};
		$kiwi -> info ("$name: [ $desc ]");
		$kiwi -> done ();
	}
	exit 0;
}

#==========================================
# listXMLInfo
#------------------------------------------
sub listXMLInfo {
	# ...
	# print information about the XML description. The
	# information listed here is for information only and
	# not specified in its format
	# ---
	my $kiwi = new KIWILog("tiny");
	my $xml  = new KIWIXML ($kiwi,$listXMLInfo,undef,$SetImageType);
	if (! defined $xml) {
		$kiwi -> failed();
		exit 1;
	}
	my %type = %{$xml->getImageTypeAndAttributes()};
	#==========================================
	# print boot information of type section
	#------------------------------------------
	if (defined $type{boot}) {
		$kiwi -> info ("Boot Type: $type{type} @ $type{boot}\n");
	} else {
		$kiwi -> info ("Boot Type: $type{type}\n");
	}
	#==========================================
	# more to come...
	#------------------------------------------
	exit 0;
}

#==========================================
# exit
#------------------------------------------
sub kiwiExit {
	# ...
	# private Exit function, exit safely
	# ---
	my $code = $_[0];
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	$kiwi -> setLogHumanReadable();
	if (! defined $LogFile) {
		my $rootLog = $kiwi -> getRootLog();
		if ((defined $rootLog) &&
			(-f $rootLog) && ($rootLog =~ /(.*)\..*\.screenrc\.log/)
		) {
			my $logfile = $1;
			$logfile = "$logfile.log";
			$kiwi -> info ("Logfile available at: $logfile");
			qxx ("mv $rootLog $logfile 2>&1");
			$kiwi -> done ();
		}
	}
	if ((defined $Survive) && ($Survive eq "yes")) {
		if ($code != 0) {
			return undef;
		}
		return $code;
	}
	if ($code != 0) {
		$kiwi -> error  ("KIWI exited with error(s)");
		$kiwi -> done ();
	} else {
		$kiwi -> info ("KIWI exited successfully");
		$kiwi -> done ();
	}
	if (defined $root) {
		$root -> cleanManager ();
	}
	$kiwi -> cleanSweep();
	exit $code;
}

#==========================================
# quit
#------------------------------------------
sub quit {
	# ...
	# signal received, exit safely
	# ---
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	} else {
		$kiwi -> reopenRootChannel();
	}
	$kiwi -> note ("\n*** $$: Received signal $_[0] ***\n");
	$kiwi -> cleanSweep();
	if (defined $boot) {
		$boot -> cleanLoop ();
	}
	if (defined $root) {
		$root  -> cleanLock   ();
		$root  -> cleanSource ();
		$root  -> cleanManager();
		$root  -> cleanMount  ();
	}
	if (defined $image) {
		$image -> cleanMount ();
		$image -> restoreSplitExtend ();
	}
	if (defined $migrate) {
		$migrate -> cleanMount ();
	}
	exit 1;
}

#==========================================
# version
#------------------------------------------
sub version {
	# ...
	# Version information
	# ---
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	my $rev  = "unknown";
	if (open FD,$Revision) {
		$rev = <FD>; close FD;
	}
	$kiwi -> info ("kiwi version v$Version SVN: Revision: $rev\n");
	$kiwi -> cleanSweep();
	exit 0;
}

#==========================================
# checkType
#------------------------------------------
sub checkType {
	my (%type) = %{$_[0]};
	my $para   = "ok";
	#==========================================
	# check filesystem tool
	#------------------------------------------
	if (defined $type{filesystem}) {
		if ($type{filesystem} eq "squashfs") {
			if (! -f "/usr/bin/mksquashfs") {
				$kiwi -> warning ("missing mksquashfs: reset to ext3 !");
				$type{filesystem} = "ext3";
				$kiwi -> skipped ();
			}
		}	
	}
	#==========================================
	# build and check KIWIImage method params
	#------------------------------------------
	SWITCH: for ($type{type}) {
		/^iso/ && do {
			if (! defined $type{boot}) {
				$kiwi -> error ("$type{type}: No boot image specified");
				$kiwi -> failed ();
				return undef;
			}
			$para = $type{boot};
			if ((defined $type{flags}) && ($type{flags} ne "")) {
				if (-f "/usr/bin/mksquashfs") {	
					$para .= ",$type{flags}";
				} else {
					$kiwi -> error("missing mksquashfs for flag: $type{flags}");
					$kiwi -> failed();
					return undef;
				}
			} 
			last SWITCH;
		};
		/^split/ && do {
			if (! defined $type{filesystem}) {
				$kiwi -> error ("$type{type}: No filesystem pair specified");
				$kiwi -> failed ();
				return undef;
			}
			$para = $type{filesystem};
			last SWITCH;
		};
		/^usb|vmx|oem|xen|pxe/ && do {
			if (! defined $type{filesystem}) {
				$kiwi -> error ("$type{type}: No filesystem specified");
				$kiwi -> failed ();
				return undef;
			}
			if (! defined $type{boot}) {
				$kiwi -> error ("$type{type}: No boot image specified");
				$kiwi -> failed ();
				return undef;
			}
			$para = $type{filesystem}.":".$type{boot};
			last SWITCH;
		};
	}
	return $para;
}

main();
