# Name:			lib_authentication_common.R
# Verson:		0.1 (2014-06-01)
# Authors:		Christian Busse
# Maintainer:	Christian Busse (busse@mpiib-berlin.mpg.de)
# Licence:		AGPL3
# Provides:		This library allows the automated selection of an appropriate authentication mechanism  .
# Requires:		lib_pipeline_common.R (func.read.config)
# 
#

config.authentication.default <- "cnf_file"
config.authentication.method <- NULL

# Test for personal authentication config file and use settings if present
#
file.name.authentication.profile <- file.path(Sys.getenv("HOME"), ".my.authentication")

if(file.exists(file.name.authentication.profile)) {
	if(exists("func.read.config")) {
		config.authentication.profile <- func.read.config(file.name.authentication.profile)
		if(! is.null(config.authentication.profile[["method"]])) {
			config.authentication.method <- config.authentication.profile[["method"]]
		} else {
			warning("lib_authentication_common: Personal authentication file exists but lacks \"method\" key. Using default authentication setting.")
		}
	} else {
		warning("lib_authentication_common: Personal authentication file exists but function \"func.read.config\" is not loaded. Using default authentication setting.")
	}
}

# If no other authentication has been found, use the default
#
if(is.null(config.authentication.method)) {
	config.authentication.method <- config.authentication.default
}

# Use the selected authentication method.
#
if(! switch(config.authentication.method,
		kwallet = { 
			source("lib/lib_authentication_kwallet.R")
			exists("getKWalletPassword")
		},
		cnf_file = {
			file.exists(file.path(Sys.getenv("HOME"), ".my.cnf"))
		}
	)
) {
	stop("Loading of selected authentication methods failed!")
}
