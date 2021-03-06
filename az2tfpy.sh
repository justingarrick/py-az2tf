usage()
{ echo "Usage: $0 -s <Subscription ID> [-g <Resource Group>] [-r azurerm_<resource_type>] [-x <yes|no(default)>] [-p <yes|no(default)>] [-f <yes|no(default)>] " 1>&2; exit 1;
}
x="no"
p="no"
f="no"  # f fast forward switch
while getopts ":s:g:r:x:p:f:" o; do
    case "${o}" in
        s)
            s=${OPTARG}
        ;;
        g)
            g=${OPTARG}
        ;;
        r)
            r=${OPTARG}
        ;;
        x)
            x="yes"
        ;;
        p)
            p="yes"
        ;;
        f)
            f="yes"
        ;;
        
        *)
            usage
        ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${s}" ]; then
    usage
fi

if [ "$s" != "" ]; then
    mysub=$s
else
    echo -n "Enter id of Subscription [$mysub] > "
    read response
    if [ -n "$response" ]; then
        mysub=$response
    fi
fi

myrg=$g
export ARM_SUBSCRIPTION_ID="$mysub"
az account set -s $mysub

echo " "
echo "Subscription ID = ${s}"
echo "Azure Resource Group Filter = ${g}"
echo "Terraform Resource Type Filter = ${r}"
echo "Get Subscription Policies & RBAC = ${p}"
echo "Extract Key Vault Secrets to .tf files (insecure) = ${x}"
echo "Fast Forward = ${f}"
echo " "

res[51]="azurerm_role_definition"
res[52]="azurerm_role_assignment"
res[53]="azurerm_policy_definition"
res[54]="azurerm_policy_assignment"

mkdir -p generated/tf.$mysub
cd generated/tf.$mysub
rm -rf .terraform
if [ "$f" = "no" ]; then
    rm -f import.log *.txt
    rm -f terraform* *.tf *.sh
else
    rm -f *$r*state*.sh import.log
fi

# cleanup from any previous runs
rm -f terraform*.backup
#rm -f terraform.tfstate
rm -f tf*.sh
cp ../../stub/*.tf .


pyc1="python2 ../../scripts/resources.py -s $mysub "
if [ "$g" != "" ]; then
    pyc2=" -g $g "
else
    pyc2=" "
fi
if [ "$r" != "" ]; then
    lcr=`echo $r | awk '{print tolower($0)}'`
    rm *$lcr*.tf
    pyc3=" -r $lcr "
else
    pyc3=" "
fi

pyc9=" 2>&1 | tee -a import.log"
pyc=`printf "%s %s %s %s" "$pyc1" "$pyc2" "$pyc3" "$pyc9"`

echo $pyc

eval $pyc
grep Error import.log
if [ $? -eq 0 ]; then
    echo "Error in resources.py"
    exit
fi


#
# uncomment following line if you want to use an SPN login
#../../setup-env.sh

echo "terraform init"
terraform init 2>&1 | tee -a import.log
echo $?



chmod 755 *state*.sh

if [ "$f" = "yes" ]; then
for com in `ls *$r*staterm.sh | sort -g`; do
    comm=`printf "./%s" $com`
    echo $comm
    eval $comm
done
fi


for com in `ls *$r*stateimp.sh | sort -g`; do
    comm=`printf "./%s" $com`
    echo $comm
    eval $comm
done





# subscription level stuff - roles & policies
if [ "$p" = "yes" ]; then
    for j in `seq 51 54`; do
        docomm="../../scripts/${res[$j]}.sh $mysub"
        echo $docomm
        eval $docomm 2>&1 | tee -a import.log
        if grep -q Error: import.log ; then
            echo "Error in log file exiting ...."
            exit
        fi
    done
fi

date

if [ "$x" = "yes" ]; then
    echo "Attempting to extract secrets"
    ../../scripts/350_key_vault_secret.sh
fi


#
echo "Cleanup Cloud Shell"
#rm -f *cloud-shell-storage*.tf
#states=`terraform state list | grep cloud-shell-storage`
#echo $states
#terraform state rm $states
#


echo "Terraform fmt ..."
terraform fmt

echo "Terraform Plan ..."
terraform plan .
echo "---------------------------------------------------------------------------"
echo "az2tf output files are in generated/tf.$mysub"
echo "---------------------------------------------------------------------------"


