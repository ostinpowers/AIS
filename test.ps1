echo 'Hostname'
echo 'Role & Description'
echo 'OSversion' 
echo 'IP'
echo 'last checked'
echo 'checked by'
echo 'CPU'
echo 'RAM'
echo 'OS drive size'
echo 

hostname
get-wmiobject win32_computersystem | fl model

