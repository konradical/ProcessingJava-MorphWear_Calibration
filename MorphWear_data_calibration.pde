/**
MorphWear processing for MetaTracker Gyro data.
Follow directions of comments below to get stuff working.
*/

//Paste filepath to data csv file from MetaTracker below between quotations
String filepath = "GyroData_10_18_2017-21_53_11.csv";
//String filepath = "testdata/Sheet 3-Table 1.csv";
Boolean header = false;

//Uncomment whichever data type was used. Uncomment by deleting the double slash // and
//adding // in front of other option. Only one option should be commneted out.

//String dataType = "accel";
String dataType = "gyro";

//Enter the sampling frequency used in Hz as selcted in the MetaWear app
int frequency = 200;

//length of target signal, column to find it, and filepath to signal
int signal_length = 18;
String signal_column = "signal";
String signal_filepath = "testdata/Sheet 2-Table 1.csv";

//Target threshold to search through signal
float threshold = -35000.0;

/** End of user inputs */
/************************************************************************************/


Table table;

void setup() {

  if (header) table = loadTable(filepath, "header, csv"); //header
  else table = loadTable(filepath, "csv"); //no header

  int rows = table.getRowCount(); //3100 //test
  int cols = table.getColumnCount(); //4 //test
  float rotation_angle = 0.0;
  println("Table row and col count: " + rows + " and " + cols);

  //Store data stream in array
  float[][] data_in = new float[cols][rows];
  for (int j = 0; j < cols; j++)
    for (int i = 0; i < rows; i++)
      data_in[j][i] = table.getFloat(i,j);
      //data_in[j][i] = table.getFloat(i,j+2);//original test table

  //Prepare the target_signal.
  //Uses vars signal_length, signal_column, and signal_filepath in user input section 
  Table signal_table = loadTable(signal_filepath, "header, csv");

  float[] target_signal = new float[signal_length];
  for (int i = 0; i < signal_length; i++)
    target_signal[i] = signal_table.getFloat(i,signal_column);

  //Initialize output array post calibration
  float[][] calibrated = new float[cols][rows];
  calibrated[0] = data_in[0]; //timestamps will remain unchanged
  calibrated[1] = data_in[1]; //X axis will remain unchanged

  //Average the input data before running it through convolution
  float[] avg100 = average100(data_in[2]);

  //Array for convolved signal that we search for metrics
  //Using data_in[2] since that has the y measurements signal
  float[] convolved_signal = convolve(avg100, target_signal);

  boolean[] threshold_met = search_threshold(convolved_signal, threshold, false);
  int[] indices = search_indices(threshold_met);

  if (indices == null) println("Error: no occurences of signal meeting threshold found");
  else
  {
    //added for debug test
    //println("Indices [a]:"+indices[0]+" [b]:"+indices[1]);
    for (int i = 0; i < indices.length; i++)
      println("Indices["+i+"]:"+indices[i]);

    int convolved_center = find_min_index(convolved_signal, indices);
    //println("Convolved center:"+convolved_center); //test

    int[] positive_peaks_indices = find_pos_peaks_indices(convolved_signal, convolved_center);
    int peak_range = positive_peaks_indices[1]-positive_peaks_indices[0];

    if (positive_peaks_indices[0] == -1 || positive_peaks_indices[1] == -1)
      println("Error: correct signal not found");
    else
    {
      int pattern_center = find_signal_center(data_in[2], positive_peaks_indices);
      println("Sweet! Calibration signal found at center " + pattern_center);

      int[] angle_calc_indices = calc_rotation_indices(pattern_center, peak_range);
      println("Using data from "+angle_calc_indices[0]+" to "+angle_calc_indices[1]+" and to "+angle_calc_indices[2]);
      rotation_angle = calc_rotation_angle(data_in[2], data_in[3], angle_calc_indices);
      println("Angle calc is: "+(rotation_angle*180/PI));

      if (apply_calibration(data_in[2], data_in[3], calibrated[2], calibrated[3], rotation_angle))
        println("Successfully calibrated data.");
      else
        println("Failed to calibrate.");
    }
  }

  Table output_file = new Table();
  output_file.addColumn("RawY");
  output_file.addColumn("RawZ");
  output_file.addColumn("CalY");
  output_file.addColumn("CalZ");
  output_file.addColumn("Angle");
  TableRow row;
  for (int i = 0; i < calibrated[1].length; i++) {
    row = output_file.addRow();
    if (i == 0) row.setFloat("Angle", rotation_angle);
    row.setFloat("RawY", data_in[2][i]);
    row.setFloat("RawZ", data_in[3][i]);
    row.setFloat("CalY", calibrated[2][i]);
    row.setFloat("CalZ", calibrated[3][i]);
  }

  saveTable(output_file, "data/output.csv", "csv");

  //size(3100,900);//orignal test
  size(2000, 900);
  plotData(data_in, calibrated, -450, 450);

  noLoop();
}

void plotData(float[][] raw, float[][] cal, int lower_limit, int upper_limit) {
  int x = 0;
  int y1 = 450, y2 = 1350;

  int[] current = new int[6];
  int[] previous = {225,225,225,675,675,675};

  background(0);

  fill(100);
  //rect(0,0,3100,450);
  rect(0,0,2000,450);

  fill(150);
  rect(0,450,2000,450);
  rect(0,450,2000,450);

  int data_limit = 2000; //3100 //test
  int data_length = raw[0].length;
  if (data_limit > data_length) data_limit = data_length;

  for (;x<data_limit;x++)
  {
    for(int i = 0; i < current.length/2; i++){
        current[i] = (450 - int(raw[i+1][x]))/2;
        current[i+3] = 450 +(450 - int(cal[i+1][x]))/2;
    }

    stroke(0xFFFF0000);
    line(x, previous[0], x+1, current[0]);

    stroke(0xFF00FF00);
    line(x, previous[1], x+1, current[1]);

    stroke(0xFF0000FF);
    line(x, previous[2], x+1, current[2]);

    stroke(0xFFFF0000);
    line(x, previous[3], x+1, current[3]);

    stroke(0xFF00FF00);
    line(x, previous[4], x+1, current[4]);

    stroke(0xFF0000FF);
    line(x, previous[5], x+1, current[5]);

    for(int i = 0; i < current.length; i++)
      previous[i] = current[i];
  }
}

boolean apply_calibration(float[] y_in, float[] z_in, float[] y_out, float[] z_out, float angle){
  if (y_in == null || z_in == null || y_out == null || z_out == null) {
    println("Incorrect input. One of float arrays is null."); return false;
  }

  int l = y_in.length;
  //println(l); //test
  //println(y_out.length); //test
  if ((z_in.length != l) || (y_out.length != l) || (z_out.length != l)) {
    println("Incorrect input. Float arrays don't match each other in length."); return false;
  }

  float q0 = cos(angle/2);
  float q1 = sin(angle/2); //see explanantion
  /* q1 changes sign accordingly with the angle, which also includes the sign switch between clockwise and counter-clockwise rotations which follow the right hand rule */

  //quick calcs
  float b = q0*q0-q1*q1;
  float c = 2*q0*q1;
  println("b: "+b+"\tc:"+c); //test

  //apply rotation
  for(int i = 0; i < l; i++){
    y_out[i] = b*y_in[i]+c*z_in[i];
    z_out[i] = b*z_in[i]-c*y_in[i];
  }

  return true;
}

float calc_rotation_angle(float[] y, float[] z, int[] range){
  float y_sum = 0.0;
  float z_sum = 0.0;

  for (int i = range[0]; i <= range[1]; i++){
    y_sum += y[i];
    z_sum += z[i];
  }

  float angle1 =  atan(z_sum/y_sum);

  y_sum = 0.0;
  z_sum = 0.0;

  for (int i = range[1]; i <= range[2]; i++){
    y_sum += y[i];
    z_sum += z[i];
  }

  float angle2 = atan(z_sum/y_sum);

  println("First angle calc is: "+angle1+"\nSecond angle calc is: "+angle2); //test

  return (angle1+angle2)/2;
}

//alternative means for calculating angle using average of atan calculations
/*float calc_rotation_angle(float[] y, float[] z, int[] range){
  float angle_sum = 0.0;

  for (int i = range[0]; i <= range[1]; i++);
    angle_sum += atan(z[i]/y[i]);

  return angle_sum/(range[1]-range[0]);
}*/

int[] calc_rotation_indices(int pattern_center, int peak_range) {
  int[] result_indices = new int[3];
  result_indices[0] = pattern_center - peak_range/2;
  result_indices[1] = pattern_center;
  result_indices[2] = pattern_center + peak_range/2;

  return result_indices;
}

int find_signal_center(float[] data, int[] indices){
  int i = indices[0];
  while (i < indices[1] && data[i] > 0) i++;
  return i;
}

int[] find_pos_peaks_indices(float[] data, int center){
  int[] indices = new int[2];
  float max = 0;
  int i = center;
  float lower_limit = center-.75*frequency; //for 200Hz sampling rate comes
  float upper_limit = center+.75*frequency; //out to search range of 150

  //search for lower index positive peak
  while (data[i] < 0) i--;
  while (i > lower_limit){
    if (data[i] > max) {
      max = data[i];
      indices[0] = i;
    }
    i--;
  }

  //check for positive peak threshold met
  if (max < .25*threshold) indices[0] = -1;

  //reset vars for finding other peak
  max = 0;
  i = center;

  //search for upper positive peak
  while (data[i] < 0) i++;
  while (i < upper_limit){
    if (data[i] > max) {
      max = data[i];
      indices[1] = i;
    }
    i++;
  }

  //check for positive peak threshold met
  if (max < -0.25*threshold) indices[1] = -1;

  return indices;
}


int find_min_index(float[] data, int[] indices){
  float min = 0.0;
  int index = 0;
  for (int i = indices[0]; i < indices[1]; i++)
    if (data[i] < min) {
      min = data[i];
      index = i;
    }
  return index;
}

int find_max_index(float[] data, int[] indices){
  float max = 0.0;
  int index = 0;
  for (int i = indices[0]; i < indices[1]; i++)
    if (data[i] > max) {
      max = data[i];
      index = i;
    }
  return index;
}

int[] search_indices(boolean[] input) {
  int occurences = 0;//, reps = 0;//reps added for test
  boolean flipped = false, previous = input[0];
  for (int i = 0; i < input.length; i++)
  {
    if (input[i] != previous) {
      //reps++;//test
      //println("a flip has begun"+reps);//test
      if (flipped) {
        occurences++;
        flipped = false;
      }
      else flipped = true;
      previous = input[i];
    }
  }

  //if 0 occurences, return null and handle outside of function
  if (occurences == 0) return null;

  //test
  println("occurences:"+occurences);

  int[] indices = new int[2*occurences];
  int count = 0;
  previous = input[0];
  for (int i = 0; i < input.length; i++)
    if(input[i] != previous){
      //println("Count:"+count);//added for test
      indices[count++] = i;
      previous = input[i];
    }
  return indices;
}

boolean[] search_threshold(float[] signal, float threshold, boolean higher){
  boolean[] threshold_met = new boolean[signal.length];

  if (higher)
    for (int i = 0; i < signal.length; i++)
      threshold_met[i] = (signal[i] > threshold);
  else
    for (int i = 0; i < signal.length; i++)
      threshold_met[i] = (signal[i] < threshold);

  return threshold_met;
}

float[] average100(float[] input) {
  //Signal will be shorter so that we don't have averages with less than 100 inputs
  float[] out = new float[input.length-99];

  float running_sum = 0.0;
  for (int i = 0; i < 100; i++)
    running_sum += input[i];

  out[0] = running_sum/100;
  for (int i = 1; i < out.length; i++) {
    running_sum = running_sum-input[i-1]+input[99+i];
    out[i] = running_sum/100;
  }

  return out;
}

float[] convolve(float[] input, float[] signal)
{
  int input_length = input.length;
  int signal_length = signal.length;
  int output_length = input_length + signal_length-1;
  float[] output = new float[output_length];
  int reps = 1;

  println("Input:  " + input_length);
  println("Signal: " + signal_length);
  println("Output: " + output_length);

  do {
    output[reps-1] = 0.0;
    for (int i = 0; i < reps; i++)
      output[reps-1] += input[reps-1-i]*signal[i];
    //println("1st stage " + reps); //increase reps for next round
    reps++;
  } //when reps is increased to signal length, loop won't run. There is equal number of input to signal
  while (reps < signal_length);

  do {
    output[reps-1] = 0.0;
    //orignal input index expression = (reps-signal_length) <--"this is the offset" + (signal_length-1-i). Simplified in actual expression
    for (int i = 0; i < signal_length; i++)
      output[reps-1] += input[reps-1-i]*signal[i];
    //println("Second stage: " + reps++);
    reps++;
  } //do for as long as the input keeps the signal buffer full, which coincides with reps equal to input length if length is known (save for stream anaylsis application)
  while (reps <= input_length);

  do {
    output[reps-1] = 0.0;
    //begins from end to keep index inside of array and loop should initially run one less than signal_length
    //index expression for input is composed by (input_length-1)-(output_length - reps -1)+(signal_length-1)-(signal_length-1-i). Simplified below
    for (int i = 0; i <= output_length - reps; i++){
      output[reps-1] += input[input_length-1-output_length+reps+i]*signal[signal_length-1-i];
      if (reps == 439){ print("Index:"+i+'.'); println(output[reps-1]);}
    }
    //println("Final stage: " + reps++);
    reps++;
  } while (reps <= output_length);

  return output;
}
