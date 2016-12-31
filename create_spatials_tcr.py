#!/usr/bin/python2.7

"""
Plot spatials for high-throughput matrix experiment.
Makefile target 'all' needs to be completed (i.e. sequences need to be in database).

Call:  create_spatials.py  <experiment_id>  <runname>   <greyscale>

Arguments:
<experiment_id>     All wells in one experiment id will be plotted. There is a statement in the title of the figure saying which different sequencing runs were included.
<runname>           This argument is needed to be able to store the figure in a defined folder. Nevertheless we include all available sequencing runs related to the experiment_id in the plot.
<greyscale>         Default: no greyscale. Use 'gs' for only greyscale and 'gs_log' for grayscale on log10(data).

Author: Katharina Imkeller
"""

# imports
import sys
import numpy as np

import matplotlib
# do not open display
matplotlib.use('Agg')
import matplotlib.pyplot as plt

import matplotlib.colorbar as cbar
import MySQLdb as mysql
from datetime import datetime as dt

import bcelldb_init as bcelldb

# get command line arguments
experiment_id = sys.argv[1]
runname = sys.argv[2]
try:
    greyscale = sys.argv[3]
except IndexError:
    greyscale = ''

# get configuration using bcelldb_init
conf = bcelldb.get_config()

# connect to database via ~/.my.conf settings
db = mysql.connect(db=conf['database'],read_default_file="~/.my.cnf", read_default_group=conf['db_group_auth'])
cursor = db.cursor()

# defining common variables
project = conf['database']

ncols, nrows = map(int, conf['matrix'].split('_'))
nrows_per_plate = int(conf['nrows_per_plate'])
ncols_per_plate = int(conf['ncols_per_plate'])
loci = ['B','A']

# np.array for the normal n_seq spatials
nseq_matrix = np.zeros((len(loci), ncols+1, nrows+1))
# np.array for booleans (calculation of probabilities)
bool_matrix = np.zeros((len(loci), ncols+1, nrows+1))

# well counts
well_count = []

# number of sequences per consensus for all three loci
for i, locus in zip(np.arange(0,len(loci),1), loci):

	# SQL query to get the number of sequences for each well
	query_statement = "SELECT n_seq, row_tag, col_tag \
			FROM %s.consensus_stats \
			JOIN %s.sequences ON consensus_stats.sequences_seq_id = sequences.seq_id \
			WHERE consensus_stats.locus = '%s' AND n_seq >= %d AND sequences.consensus_rank = 1 \
			AND experiment_id='%s';" % (project, project, locus, int(conf['n_consensus']), experiment_id)

	cursor.execute(query_statement)
	consensus_rows = cursor.fetchall()

	# total number of reads
	well_count.append(len(consensus_rows))

	# for each consensus store nseq into matrix at row/sol position
	for consensus in consensus_rows:
         row_tag = int(consensus[1][1:])
         col_tag = int(consensus[2][1:])
         bool_matrix[i, col_tag, row_tag] = 1
         nseq_matrix[i, col_tag, row_tag] = consensus[0]

# total number of events
total_events = nrows*ncols

# beta and alpha frequency alone
total_beta = np.sum(bool_matrix[0], dtype=np.float64)
total_alpha = np.sum(bool_matrix[1], dtype=np.float64)

# beta with alpha
beta_when_alpha = np.sum(bool_matrix[0]+bool_matrix[1] >= 2, dtype=np.float64)

# random association (H*light)

total_freq_annot = "Total frequencies:\n\n\
P(beta) = %.2f\n\
P(alpha) = %.2f\n\n" % (total_beta/total_events,
    total_alpha/total_events)

conditional_freq_annot = "Combined frequencies:\n\n\
P(beta and alpha) = %.2f\n\n" % (beta_when_alpha/total_events)

random_association = "Random association model:\n\n\
P(beta) * P(alpha) = %.2f\n\n" % (total_beta/total_events*total_alpha/total_events)

annotation = total_freq_annot + conditional_freq_annot + random_association
print annotation



def matrix_plot(matrix,title):
    """
    Plot transposed matrix in grey scale. Plates delimited by grid.
    """
    if greyscale[-3:] == 'log':
        matrix = np.log10(matrix + 1)
    ax = plt.imshow(matrix.T, cmap='binary', interpolation='none')
    plt.title(title, fontsize=24)
    plt.xticks(np.arange(ncols_per_plate-0.5,ncols-0.5,ncols_per_plate))
    plt.yticks(np.arange(nrows_per_plate-0.5,nrows-0.5,nrows_per_plate))
    plt.grid(which='major', linestyle='-')
    plt.tick_params(bottom='off', top='off', right='off', left='off', labelbottom='off', labeltop='off', labelright='off', labelleft='off')
    return ax


# plot spatials

fig = plt.figure(figsize = (30,15))

if greyscale[0:2] == 'gs':
    if greyscale[-3:] == 'log':
        label = 'log10(Number of reads per well + pseudocount)'
    else:
        label = 'Number of reads per well'
    plt.subplot(1,3,1)
    ax1 = matrix_plot(nseq_matrix[0, 1:,1:], "beta chain\n")
    plt.colorbar(ax1, shrink = 0.4).set_label(label)
    plt.subplot(1,3,2)
    ax2 = matrix_plot(nseq_matrix[1, 1:,1:], "alpha chain\n")
    plt.colorbar(ax2, shrink = 0.4).set_label(label)
else:
    plt.subplot(1,3,1)
    matrix_plot(bool_matrix[0, 1:,1:], "beta chain\n")
    plt.subplot(1,3,2)
    matrix_plot(bool_matrix[1, 1:,1:], "alpha chain\n")

plt.figtext(0.15,0.25, total_freq_annot, verticalalignment = 'top', fontsize = 20)
plt.figtext(0.45,0.25,conditional_freq_annot, verticalalignment = 'top', fontsize = 20)
plt.figtext(0.7,0.25,random_association, verticalalignment = 'top', fontsize = 20)




# logging in the figure title

# find out which sequencing runs were included in the plot
runs_query_statement = "SELECT sequencing_run.name \
    FROM %s.consensus_stats \
    JOIN %s.sequences ON consensus_stats.sequences_seq_id = sequences.seq_id \
    JOIN %s.reads ON consensus_stats.consensus_id = reads.consensus_id \
    JOIN %s.sequencing_run ON sequencing_run.sequencing_run_id = reads.sequencing_run_id \
    WHERE n_seq >= %d AND sequences.consensus_rank = 1 \
    AND consensus_stats.experiment_id='%s' \
    GROUP BY sequencing_run.name;" % (project, project, project, project, int(conf['n_consensus']), experiment_id)

cursor.execute(runs_query_statement)
runs_rows = cursor.fetchall()
# build the string for all runnames
runnames = ''
for run in runs_rows:
    # ", " will need to be removed for the last insertion
    runnames = runnames + run[0] + ", "

date = dt.now().strftime('%Y-%m-%d %H:%M:%S')
title = "Spatials and detection efficiencies for runs (%s) from database %s on %s" % (runnames[:-2], project, date)

plt.suptitle(title, fontsize = 25, y=0.80)

plt.savefig("../quality_control/"+runname+"/"+experiment_id+"_"+runname+"_spatials.pdf")
