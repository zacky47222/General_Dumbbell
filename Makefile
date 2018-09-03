RUN_srcs:=Integrate.f90 \
Generate_Initial_Conditions.f90 \
Dumbbell_util.f90 \
main.f90

RUN_objs=$(patsubst %.f90,%.o,$(RUN_srcs))

TEST_srcs:=Integrate.f90 \
Generate_Initial_Conditions.f90 \
Dumbbell_util.f90 \
Dumbbell_Validation_Tests.f90 \
fruit.f90

TEST_objs=$(patsubst %.f90,%.o,$(TEST_srcs))

SRC_DIR = src/
RUN_DIR = run/
TEST_DIR = tests/
FC = ifort
CFLAGS = -O3 -fopenmp

run: $(RUN_objs)
	@mkdir -p $(RUN_DIR)
	$(FC) -o $(RUN_DIR)main.out $(CFLAGS) $(RUN_objs)
	@cp inputs/*.inp $(RUN_DIR)

test: $(TEST_objs)
	@mkdir -p $(TEST_DIR)
	$(FC) -o $(TEST_DIR)tests.out $(CFLAGS) $(TEST_objs)

clean:
	rm *.mod *.o

# Dependencies of files
Dumbbell_Validation_Tests.o: \
	$(SRC_DIR)Dumbbell_Validation_Tests.f90 \
    Dumbbell_util.o \
    fruit.o \
    Generate_Initial_Conditions.o \
    Integrate.o
	$(FC) -c $(SRC_DIR)Dumbbell_Validation_Tests.f90 $(CFLAGS)
fruit.o: $(SRC_DIR)fruit.f90
	$(FC) -c $(SRC_DIR)fruit.f90 $(CFLAGS)
Integrate.o: \
    $(SRC_DIR)Integrate.f90 \
    Dumbbell_util.o
	$(FC) -c $(SRC_DIR)Integrate.f90 $(CFLAGS)
Generate_Initial_Conditions.o: \
    $(SRC_DIR)Generate_Initial_Conditions.f90 \
    Dumbbell_util.o
	$(FC) -c $(SRC_DIR)Generate_Initial_Conditions.f90 $(CFLAGS)
Dumbbell_util.o: \
    $(SRC_DIR)Dumbbell_util.f90
	$(FC) -c $(SRC_DIR)Dumbbell_util.f90 $(CFLAGS)
main.o: \
    $(SRC_DIR)main.f90 \
    Dumbbell_util.o \
    Generate_Initial_Conditions.o \
    Integrate.o
	$(FC) -c $(SRC_DIR)main.f90 $(CFLAGS)
