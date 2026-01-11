defmodule X12Bridge.X12.Qualifiers do
  @moduledoc """
  X12 Qualifier and Code Lookups

  Provides human-readable descriptions for X12 qualifiers and codes.
  Returns the code itself if no description is found (defensive approach).
  """

  @doc """
  Get description for NM1 entity identifier code
  """
  def entity_code(code) do
    case code do
      "40" -> "Receiver"
      "41" -> "Submitter"
      "71" -> "Attending Physician"
      "72" -> "Operating Physician"
      "77" -> "Service Location"
      "82" -> "Rendering Provider"
      "85" -> "Billing Provider"
      "87" -> "Pay-to Provider"
      "DN" -> "Referring Provider"
      "DQ" -> "Supervising Provider"
      "IL" -> "Insured/Subscriber"
      "P3" -> "Primary Care Provider"
      "PR" -> "Payer"
      "QC" -> "Patient"
      "X3" -> "Dependent"
      _ -> code  # Return code if unknown
    end
  end

  @doc """
  Get description for DTP date/time qualifier
  """
  def date_qualifier(code) do
    case code do
      "096" -> "Discharge Date"
      "097" -> "Discharge Hour"
      "098" -> "Admission Date"
      "291" -> "Statement From Date"
      "292" -> "Statement To Date"
      "304" -> "Last Visit Date"
      "318" -> "Symptom Date"
      "319" -> "Last X-Ray Date"
      "431" -> "Onset of Current Symptoms"
      "435" -> "Admission Date/Hour"
      "439" -> "Accident Date"
      "453" -> "Acute Manifestation Date"
      "454" -> "Initial Treatment Date"
      "455" -> "Last Seen Date"
      "471" -> "Prescription Date"
      "472" -> "Service Date"
      "573" -> "Certification Date"
      "607" -> "Disability From Date"
      "610" -> "Disability Through Date"
      _ -> code
    end
  end

  @doc """
  Get description for REF reference identification qualifier
  """
  def reference_qualifier(code) do
    case code do
      "0B" -> "State License Number"
      "1A" -> "Blue Cross Provider Number"
      "1B" -> "Blue Shield Provider Number"
      "1C" -> "Medicare Provider Number"
      "1D" -> "Medicaid Provider Number"
      "1G" -> "Provider UPIN Number"
      "1H" -> "CHAMPUS Identification Number"
      "1J" -> "Facility ID Number"
      "4A" -> "Investigation Number"
      "6R" -> "Provider Control Number"
      "9A" -> "Repriced Claim Number"
      "9C" -> "Repriced Line Item Reference"
      "D3" -> "Membership Number"
      "D9" -> "Prior Authorization Number"
      "EA" -> "Medical Record Identification Number"
      "EI" -> "Employer ID Number"
      "F5" -> "Medicare Version Code"
      "F8" -> "Original Reference Number"
      "G1" -> "Referral Number"
      "G3" -> "Location Number"
      "LU" -> "Location Number"
      "SY" -> "Social Security Number"
      "X4" -> "Clinical Laboratory Improvement Amendment Number"
      "Y4" -> "Agency Claim Number"
      _ -> code
    end
  end

  @doc """
  Get description for claim filing indicator code (CLM05-01)
  """
  def claim_filing_indicator(code) do
    case code do
      "09" -> "Self Pay"
      "11" -> "Other Non-Federal Programs"
      "12" -> "Preferred Provider Organization (PPO)"
      "13" -> "Point of Service (POS)"
      "14" -> "Exclusive Provider Organization (EPO)"
      "15" -> "Indemnity Insurance"
      "16" -> "Health Maintenance Organization (HMO) Medicare Risk"
      "AM" -> "Automobile Medical"
      "BL" -> "Blue Cross/Blue Shield"
      "CH" -> "CHAMPUS"
      "CI" -> "Commercial Insurance Co."
      "DS" -> "Disability"
      "FI" -> "Federal Employees Program"
      "HM" -> "Health Maintenance Organization"
      "LM" -> "Liability Medical"
      "MA" -> "Medicare Part A"
      "MB" -> "Medicare Part B"
      "MC" -> "Medicaid"
      "OF" -> "Other Federal Program"
      "TV" -> "Title V"
      "VA" -> "Veterans Affairs Plan"
      "WC" -> "Workers Compensation Health Claim"
      "ZZ" -> "Mutually Defined"
      _ -> code
    end
  end

  @doc """
  Get description for diagnosis code qualifier
  """
  def diagnosis_qualifier(code) do
    case code do
      "ABF" -> "ICD-10-CM (Admitting Diagnosis)"
      "ABJ" -> "ICD-10-CM (Principal Diagnosis)"
      "ABK" -> "ICD-10-CM (Principal Diagnosis)"
      "APR" -> "ICD-10-CM (Principal Procedure)"
      "BF" -> "ICD-9-CM (Admitting Diagnosis)"
      "BJ" -> "ICD-9-CM (Principal Diagnosis)"
      "BK" -> "ICD-9-CM (Principal Diagnosis)"
      "PR" -> "ICD-9-CM (Principal Procedure)"
      _ -> code
    end
  end

  @doc """
  Get description for place of service code
  """
  def place_of_service(code) do
    case code do
      "01" -> "Pharmacy"
      "02" -> "Telehealth Provided Other than in Patient's Home"
      "10" -> "Telehealth Provided in Patient's Home"
      "11" -> "Office"
      "12" -> "Home"
      "21" -> "Inpatient Hospital"
      "22" -> "On Campus-Outpatient Hospital"
      "23" -> "Emergency Room - Hospital"
      "24" -> "Ambulatory Surgical Center"
      "31" -> "Skilled Nursing Facility"
      "32" -> "Nursing Facility"
      "33" -> "Custodial Care Facility"
      "34" -> "Hospice"
      "41" -> "Ambulance - Land"
      "42" -> "Ambulance - Air or Water"
      "49" -> "Independent Clinic"
      "50" -> "Federally Qualified Health Center"
      "51" -> "Inpatient Psychiatric Facility"
      "52" -> "Psychiatric Facility-Partial Hospitalization"
      "53" -> "Community Mental Health Center"
      "54" -> "Intermediate Care Facility/Individuals with Intellectual Disabilities"
      "55" -> "Residential Substance Abuse Treatment Facility"
      "56" -> "Psychiatric Residential Treatment Center"
      "57" -> "Non-residential Substance Abuse Treatment Facility"
      "60" -> "Mass Immunization Center"
      "61" -> "Comprehensive Inpatient Rehabilitation Facility"
      "62" -> "Comprehensive Outpatient Rehabilitation Facility"
      "65" -> "End-Stage Renal Disease Treatment Facility"
      "71" -> "Public Health Clinic"
      "72" -> "Rural Health Clinic"
      "81" -> "Independent Laboratory"
      "99" -> "Other Place of Service"
      _ -> code
    end
  end
end
