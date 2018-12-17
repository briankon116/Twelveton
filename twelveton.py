from __future__ import print_function
import subprocess, argparse, sys, os
from shutil import copyfile

parser = argparse.ArgumentParser(description='Generate 12-Tone Music using Prolog')
parser.add_argument('-c', '--compose', action='store_true', help='Set program in compose mode to generate new twelve tone piece')
parser.add_argument('-v', '--validate', type=str, help='Validate an existing composition from a file')
parser.add_argument('-o', '--outputFile', type=str, help='Output file location')
parser.add_argument('--antonOutput', type=str, help='Format to output from anton. Options are: human, lilypond, csound')
parser.add_argument('-l', '--length', type=int, help='Length of song to generate if in compose mode.')
parser.add_argument('ToneRow', type=str, nargs='?', help='Tone row to use for either composing or verifying. Ex: [1,5,6,7,2,3,9,4,10,11,0,8]')
args = parser.parse_args()


class TwelveTone:

	def __init__(self, args):
		self.args = args

		self.validate_args()
		if(self.args.validate):
			self.validate()
		if(self.args.compose):
			self.compose()

	def validate_args(self):
		if(not self.args.ToneRow):
			parser.print_help()
			sys.exit(0)
		if(self.args.compose and not self.args.length):
			parser.print_help()
			sys.exit(0)

	def compose(self):
		subprocess.call('xsb --nobanner --noprompt --quietload -e "consult(composition),compose(%s,%d,M),halt."' % (str(self.args.ToneRow), self.args.length), shell=True)

		f = open('antonOutput', 'r')

		line = f.readline()
		notes = line.split('[')[1].split(']')[0].split(',')
		notes = [int(note) for note in notes]
		intervals = [notes[i+1] - notes[i] for i in range(0,len(notes)-1)]
		numNotes = len(notes)

		f.close()

		f = open('antonOutput', 'w')

		f.write('clasp version 3.2.0\n')
		f.write('Reading from stdin\n')
		f.write('Solving...\n')
		f.write('Answer: 1\n')
		f.write('mode(major) part(1) partTimeMax(1,%d) ' % numNotes)

		for i in range(1,numNotes+1):
			f.write('partTime(1,%d) ' % i)

		counter = 1
		for interval in intervals:
			f.write('stepBy(1,%d,%d) ' % (counter,interval))
			counter+=1

		counter = 1
		for note in notes:
			f.write('choosenNote(1,%d,%d) ' % (counter, note+25))
			counter+=1
		f.close()

		if(self.args.antonOutput):
			os.chdir('anton_parser')
			subprocess.call('./parse.pl --output=' + self.args.antonOutput + ' < ../antonOutput', shell=True)
			os.chdir('../')
			
		if(self.args.outputFile):
			copyfile('antonOutput', self.args.outputFile)

		os.remove('antonOutput')

	def validate(self):
		f = open(args.validate)

		f.readline()
		f.readline()
		f.readline()
		f.readline()
		line = f.readline()
		f.close()

		elements = line.split(' ')
		notes = [element for element in elements if 'choosenNote' in element]
		notes = [int(note.split(',')[-1].split(')')[0]) - 25 for note in notes]
		
		subprocess.call('xsb --noprompt --nobanner --quietload -e "consult(validation),validate(%s,%d,%s),halt."' % (str(self.args.ToneRow), len(notes), notes), shell=True)
		
		f = open('antonOutput')
		line = f.readline()

		if(line == 'yes'):
			print('Composition is a valid 12-Tone piece')
		else:
			print('Composition is not a valid 12-Tone piece')		
		
		os.remove('antonOutput')

twelveTone = TwelveTone(args)
