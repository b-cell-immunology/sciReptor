#!/usr/bin/env python-2.7
"""
Module for common processes in bcelldb computing:
	get information from config file
"""

import re

def get_config():
	"""
	Look for config file in . and than ../
	Return config key value pairs in dictionnary conf[].
	"""
	
	# try to open config file in .
	try:
		config_file = open("config","r")

	except IOError:
		# try from ../ directory
		try:
			config_file = open("../config", "r")
		except IOError:
			print "no config file found"

	# global dicctionary conf that will be exported
	conf = dict()
	
	# read lines of config
	for line in config_file:
		# every line with # is used as a comment line
		if re.search('=', line) and not re.match('\s?#', line):
			# split entries into key-value
			[key, value] = re.split("=", line)
                # get rid of new line
			conf[key] = value[:-1]

	# return conf[]
	return conf 

