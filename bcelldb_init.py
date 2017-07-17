#!/usr/bin/env python-2.7
"""
Module for common processes in bcelldb computing:
	get information from config file
"""

import re
re_key_value = re.compile("^\s*([_A-Za-z][_0-9A-Za-z]+)=(.*?)\s*;?\s*$")
re_inline_comment = re.compile("^(.*?)(?<!\\\\)#.*")

def get_config():
	"""
	Look for config file in . and than ../
	Return config key value pairs in dictionary conf[].
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

	# global dictionary conf that will be exported
	conf = dict()
	
	# read lines of config
	for line in config_file:
		line = line.rstrip()
		if not re.match("^\s*$", line) and not re.match("^\s*#", line):
			# Split entries into key-value.
			line = re_inline_comment.sub('\g<1>', line)
			key, value = re_key_value.match(line).group(1,2)
			conf[key] = value

	return conf 

