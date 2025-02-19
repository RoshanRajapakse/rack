#!/bin/bash

function assert_run {
  run "$1" || { echo "failed"; exit 101; }
}

function fetch {
  fetch_once $1 && sleep 5 && fetch_once $1
}

function fetch_once {
  curl -ks --connect-timeout 5 --max-time 3 --retry 100 --retry-max-time 600 --retry-connrefused $1
}

function run {
  echo "running: $*" >&2
  eval $*
}

root="$(cd $(dirname ${0:-})/..; pwd)"

set -ex

provider=$(convox api get /system | jq -r .provider)
source $(dirname $0)/env.sh

# cli
convox version

# rack
convox instances
convox rack
sleep 15
convox rack logs --no-follow | grep service/
convox rack ps | grep rack

convox racks | grep ${RACK_NAME}

# rack (provider-specific)
case $provider in
  aws)
    convox rack releases
    convox instances keyroll --wait
    instance=$(convox api get /instances | jq -r '.[0].id')
    convox instances ssh $instance "ls -la" | grep ec2-user
    convox instances terminate $instance
    convox rack | grep elb.amazonaws.com
    convox rack params | grep LogRetention
    convox rack params set LogRetention=14 --wait
    convox rack params | grep LogRetention | grep 14
    convox rack params set LogRetention= --wait
    convox rack params | grep LogRetention | grep -v 14
    ;;
esac

# app
cd $root/examples/httpd

if [ "${ACTION}" != "" ]; then
  # if update or downgrade test, it will deploy the app again
  convox deploy -a ci2 --wait
fi

convox apps | grep ci2
convox apps info ci2 | grep running
release=$(convox build -a ci2 -d cibuild --id) && [ -n "$release" ]
convox releases -a ci2 | grep $release
build=$(convox api get /apps/ci2/builds | jq -r ".[0].id") && [ -n "$build" ]
convox builds -a ci2 | grep $build
convox builds info $build -a ci2 | grep $build
convox builds info $build -a ci2 | grep cibuild
convox builds logs $build -a ci2 | grep "Running: docker push"
convox builds export $build -a ci2 -f /tmp/build.tgz
releasei=$(convox builds import -a ci2 -f /tmp/build.tgz --id) && [ -n "$releasei" ]
buildi=$(convox api get /apps/ci2/releases/$releasei | jq -r ".build") && [ -n "$buildi" ]
convox builds info $buildi -a ci2 | grep cibuild
echo "FOO=bar" | convox env set -a ci2
convox env -a ci2 | grep FOO | grep bar
convox env get FOO -a ci2 | grep bar
convox env unset FOO -a ci2
convox env -a ci2 | grep -v FOO
releasee=$(convox env set FOO=bar -a ci2 --id) && [ -n "$releasee" ]
convox env get FOO -a ci2 | grep bar
convox releases -a ci2 | grep $releasee
convox releases info $releasee -a ci2 | grep FOO
convox releases manifest $releasee -a ci2 | grep "build: ."
convox releases promote $release -a ci2 --wait
endpoint=$(convox api get /apps/ci2/services | jq -r '.[] | select(.name == "web") | .domain')
fetch https://$endpoint | grep "It works"
convox logs -a ci2 --no-follow | grep service/web
releaser=$(convox releases rollback $release -a ci2 --wait --id)
convox ps -a ci2 | grep $releaser
ps=$(convox api get /apps/ci2/processes | jq -r '.[]|select(.status=="running")|.id' | head -n 1)
convox ps info $ps -a ci2 | grep $releaser
convox scale web --count 2 --cpu 192 --memory 256 -a ci2 --wait
convox services -a ci2 | grep web | grep 443:80 | grep $endpoint
endpoint=$(convox api get /apps/ci2/services | jq -r '.[] | select(.name == "web") | .domain')
fetch https://$endpoint | grep "It works"
convox ps -a ci2 | grep web | wc -l | grep 2
ps=$(convox api get /apps/ci2/processes | jq -r '.[]|select(.status=="running")|.id' | head -n 1)
convox exec $ps "ls -la" -a ci2 | grep htdocs
cat /dev/null | convox exec $ps 'sh -c "sleep 2; echo test"' -a ci2 | grep test
convox run web "ls -la" -a ci2 | grep htdocs
cat /dev/null | convox run web 'sh -c "sleep 2; echo test"' -a ci2 | grep test
echo foo > /tmp/file
convox cp /tmp/file $ps:/file -a ci2
convox exec $ps "cat /file" -a ci2 | grep foo
mkdir -p /tmp/dir
echo foo > /tmp/dir/file
convox cp /tmp/dir $ps:/dir -a ci2
convox exec $ps "cat /dir/file" -a ci2 | grep foo
convox cp $ps:/dir /tmp/dir2 -a ci2
cat /tmp/dir2/file | grep foo
convox cp $ps:/file /tmp/file2 -a ci2
cat /tmp/file2 | grep foo
convox ps stop $ps -a ci2
convox ps -a ci2 | grep -v $ps
convox deploy -a ci2 --wait
ps=$(convox api get /apps/ci2/processes | jq -r '.[]|select(.status=="running")|.id' | head -n 1)
# postgres resource
convox exec -a ci2 $ps -- env | grep "POSTGRES_URL"
convox exec -a ci2 $ps -- env | grep "POSTGRES_USER"
convox exec -a ci2 $ps -- env | grep "POSTGRES_PASS"
convox exec -a ci2 $ps -- env | grep "POSTGRES_HOST"
convox exec -a ci2 $ps -- env | grep "POSTGRES_PORT"
convox exec -a ci2 $ps -- env | grep "POSTGRES_NAME"
# mysql resource
convox exec -a ci2 $ps -- env | grep "MYSQL_URL"
convox exec -a ci2 $ps -- env | grep "MYSQL_USER"
convox exec -a ci2 $ps -- env | grep "MYSQL_PASS"
convox exec -a ci2 $ps -- env | grep "MYSQL_HOST"
convox exec -a ci2 $ps -- env | grep "MYSQL_PORT"
convox exec -a ci2 $ps -- env | grep "MYSQL_NAME"
# mariadb resource
convox exec -a ci2 $ps -- env | grep "MARIADB_URL"
convox exec -a ci2 $ps -- env | grep "MARIADB_USER"
convox exec -a ci2 $ps -- env | grep "MARIADB_PASS"
convox exec -a ci2 $ps -- env | grep "MARIADB_HOST"
convox exec -a ci2 $ps -- env | grep "MARIADB_PORT"
convox exec -a ci2 $ps -- env | grep "MARIADB_NAME"

# test apps cancel
echo "FOO=not-bar" | convox env set -a ci2

cp Dockerfile Dockerfile.original # copy current Dockerfile
echo "COPY new-feature.html /usr/local/apache2/htdocs/index.html" >> Dockerfile
echo "ENTRYPOINT sleep 60 && httpd-foreground" >> Dockerfile
convox deploy -a ci2 # won't use --wait, we want it to run in the background

i=0
while [ "$(convox apps info -a ci2 | grep updating | wc -l)" != "1" ]
do
  # exit if takes more than 60 seconds/times
  if [ $((i++)) -gt 60 ]; then
    exit 1
  fi
  echo "waiting for web to be marked as updating..."
  sleep 1
done

echo "app is updating will cancel in 10 secs"
sleep 10

convox apps cancel -a ci2 --wait | grep "OK"
echo "app deployment canceled"

endpoint=$(convox api get /apps/ci2/services | jq -r '.[] | select(.name == "web") | .domain')
fetch https://$endpoint | grep "It works"
echo "still returning the right content"

convox env -a ci2 | grep "FOO" | grep "not-bar"
echo "env var is correctly set"

mv Dockerfile.original Dockerfile # replace the Dockerfile with the original copy

# registries
convox registries
convox registries add quay.io convox+ci 6D5CJVRM5P3L24OG4AWOYGCDRJLPL0PFQAENZYJ1KGE040YDUGPYKOZYNWFTE5CV
convox registries | grep quay.io | grep convox+ci
convox build -a ci2 | grep -A 5 "Authenticating https://quay.io" | grep "Login Succeeded"
convox registries remove quay.io
convox registries | grep -v quay.io

# app (provider-specific)
case $provider in
  aws)
    convox apps params -a ci2 | grep LogRetention
    convox apps params set LogRetention=14 -a ci2 --wait
    convox apps params -a ci2 | grep LogRetention | grep 14
    convox apps params set LogRetention= -a ci2 --wait
    convox apps params -a ci2 | grep LogRetention | grep -v 14
    ;;
esac

# gen1
case $provider in
  aws)
    cd $root/examples/httpd
    convox apps create ci1 -g 1 --wait
    convox deploy -a ci1 --wait
    convox services -a ci1 | grep web | grep elb.amazonaws.com | grep 443:80
    endpoint=$(convox api get /apps/ci1/services | jq -r '.[] | select(.name == "web") | .domain')
    fetch https://$endpoint | grep "It works"
    ;;
esac

# test internal communication and internal apps
case $provider in
  aws)
    cd $root/examples/internal
    # test without internal attribute
    convox apps create internal1 --wait
    convox deploy -a internal1 --wait
    convox apps create internal2 --wait
    convox deploy -a internal2 --wait

    endpoint=$(convox api get /apps/internal1/services | jq -r '.[] | select(.name == "web") | .domain')
    fetch https://$endpoint | grep "It works"
    endpoint=$(convox api get /apps/internal2/services | jq -r '.[] | select(.name == "web") | .domain')
    fetch https://$endpoint | grep "It works"

    rackname=$(convox rack | grep 'Name' | xargs | cut -d ' ' -f2 )
    ## from internal1 to internal2
    ps1=$(convox api get /apps/internal1/processes | jq -r '.[]|select(.status=="running" and .name == "web")|.id' | head -n 1)
    convox exec $ps1 "curl -k https://web.internal2.$rackname.convox" -a internal1 | grep "It works"

    ## from internal2 to internal1
    ps2=$(convox api get /apps/internal2/processes | jq -r '.[]|select(.status=="running" and .name == "web")|.id' | head -n 1)
    convox exec $ps2 "curl -k https://web.internal1.$rackname.convox" -a internal2 | grep "It works"

    # test with internal as true
    mv convox-internal.yml convox.yml
    convox rack params set Internal=Yes --wait
    convox deploy -a internal1 --wait
    convox deploy -a internal2 --wait

    ## external communication should not work
    endpoint=$(convox api get /apps/internal1/services | jq -r '.[] | select(.name == "web") | .domain')
    $root/ci/additonal-test/fetch-timeout.sh https://$endpoint "internal apps should not be reachable outside of the rack"

    endpoint=$(convox api get /apps/internal2/services | jq -r '.[] | select(.name == "web") | .domain')
    $root/ci/additonal-test/fetch-timeout.sh https://$endpoint "internal apps should not be reachable outside of the rack"

    ## from internal1 to internal2
    ps1=$(convox api get /apps/internal1/processes | jq -r '.[]|select(.status=="running" and .name == "web")|.id' | head -n 1)
    convox exec $ps1 "curl -k https://web.internal2.$rackname.convox" -a internal1 | grep "It works"

    ## from internal2 to internal1
    ps2=$(convox api get /apps/internal2/processes | jq -r '.[]|select(.status=="running" and .name == "web")|.id' | head -n 1)
    convox exec $ps2 "curl -k https://web.internal1.$rackname.convox" -a internal2 | grep "It works"

    # clean up
    convox apps delete internal1 --wait
    convox apps delete internal2 --wait
    convox rack params set Internal=No --wait
    ;;
esac

# timers
sleep 30

timerLog=$(convox logs -a ci2 --no-follow --since 1m | grep service/example)
if ! [[ $timerLog == *"Hello Timer"* ]]; then
  echo "failed"; exit 1;
fi

# certs
case $provider in
  aws)
    cd $root/ci/assets
    convox certs
    cert=$(convox certs generate example.org --id)
    convox certs | grep -v $cert
    convox certs delete $cert
    cert=$(convox certs import example.org.crt example.org.key --id)
    sleep 30
    convox certs | grep $cert
    certo=$(convox api get /apps/ci1/services | jq -r '.[] | select(.name == "web") | .ports[] | select (.balancer == 443) | .certificate')
    convox ssl -a ci1 | grep web:443 | grep $certo
    convox ssl update web:443 $cert -a ci1 --wait
    convox ssl -a ci1 | grep web:443 | grep $cert
    convox ssl update web:443 $certo -a ci1 --wait
    convox ssl -a ci1 | grep web:443 | grep $certo
    sleep 30
    convox certs delete $cert
    ;;
esac

# rack resources
case $provider in
  aws)
    convox rack resources create syslog Url=tcp://syslog.convox.com --name cilog --wait
    convox rack resources | grep cilog | grep syslog
    convox rack resources info cilog | grep -v Apps
    convox rack resources url cilog | grep tcp://syslog.convox.com
    convox rack resources link cilog -a ci2 --wait
    convox rack resources info cilog | grep Apps | grep ci2
    convox rack resources unlink cilog -a ci2 --wait
    convox rack resources info cilog | grep -v Apps
    convox rack resources link cilog -a ci1 --wait
    convox rack resources info cilog | grep Apps | grep ci1
    convox rack resources unlink cilog -a ci1 --wait
    convox rack resources info cilog | grep -v Apps
    convox rack resources update cilog Url=tcp://syslog2.convox.com --wait
    convox rack resources info cilog | grep syslog2.convox.com
    convox rack resources url cilog | grep tcp://syslog2.convox.com
    convox rack resources delete cilog --wait
    convox rack resources create postgres --name pgdb --wait
    convox rack resources | grep pgdb | grep postgres
    dburl=$(convox rack resources url pgdb)
    convox rack resources update pgdb BackupRetentionPeriod=2 --wait
    [ "$dburl" == "$(convox rack resources url pgdb)" ]
    convox rack resources delete pgdb --wait
    ;;
esac

# cleanup
convox apps delete ci2 --wait

# cleanup (provider-specific)
case $provider in
  aws)
    convox apps delete ci1 --wait
    ;;
esac
