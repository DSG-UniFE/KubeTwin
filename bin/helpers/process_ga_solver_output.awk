BEGIN { print "Generation,Value" }
/> gen*/ { print $9 $NF }

