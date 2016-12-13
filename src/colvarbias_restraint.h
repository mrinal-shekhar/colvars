// -*- c++ -*-

#ifndef COLVARBIAS_RESTRAINT_H
#define COLVARBIAS_RESTRAINT_H

#include "colvarbias.h"

/// \brief Most general definition of a colvar restraint:
/// see derived classes for specific types
/// (implementation of \link colvarbias \endlink)
class colvarbias_restraint
  : public virtual colvarbias
{

public:

  /// Retrieve colvar values and calculate their biasing forces
  virtual int update();

  // TODO the following can be supplanted by a new call to init()
  /// Load new configuration - force constant and/or centers only
  virtual void change_configuration(std::string const &conf) {}

  /// TODO Calculate change in energy from using alternate configuration
  virtual cvm::real energy_difference(std::string const &conf) { return 0.0; }

  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);
  // virtual std::ostream & write_state_data(std::ostream &os);
  // virtual std::istream & read_state_data(std::istream &os);
  virtual std::ostream & write_state(std::ostream &os);
  virtual std::istream & read_state(std::istream &is);

  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

  /// \brief Constructor
  colvarbias_restraint(char const *key);

  virtual int init(std::string const &conf);
  virtual ~colvarbias_restraint();


protected:

  /// \brief Potential function for the i-th colvar
  virtual cvm::real restraint_potential(size_t i) const = 0;

  /// \brief Force function for the i-th colvar
  virtual colvarvalue const restraint_force(size_t i) const = 0;

  /// \brief Derivative of the potential function with respect to the force constant
  virtual cvm::real d_restraint_potential_dk(size_t i) const = 0;
};


/// Definition and parsing of the restraint centers
class colvarbias_restraint_centers
  : public virtual colvarbias_restraint
{
public:

  colvarbias_restraint_centers(char const *key);
  virtual int init(std::string const &conf);

protected:

  /// \brief Restraint centers
  std::vector<colvarvalue> colvar_centers;

  /// \brief Restraint centers outside the domain of the colvars (no wrapping or constraints applied)
  std::vector<colvarvalue> colvar_centers_raw;
};


/// Definition and parsing of the force constant
class colvarbias_restraint_k
  : public virtual colvarbias_restraint
{
public:

  colvarbias_restraint_k(char const *key);
  virtual int init(std::string const &conf);

protected:
  /// \brief Restraint force constant
  cvm::real force_k;
};


/// Options to change the restraint configuration over time (shared between centers and k moving)
class colvarbias_restraint_moving
  : public virtual colvarparse {
public:

  colvarbias_restraint_moving(char const *key);
  // Note: despite the diamond inheritance, most of this function gets only executed once
  virtual int init(std::string const &conf);
  virtual int update() { return COLVARS_OK; }
  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);

protected:

  /// \brief Moving target?
  bool b_chg_centers;

  /// \brief Changing force constant?
  bool b_chg_force_k;

  /// \brief Number of stages over which to perform the change
  /// If zero, perform a continuous change
  int target_nstages;

  /// \brief Number of current stage of the perturbation
  int stage;

    /// \brief Lambda-schedule for custom varying force constant
  std::vector<cvm::real> lambda_schedule;

  /// \brief Number of steps required to reach the target force constant
  /// or restraint centers
  long target_nsteps;
};


/// Options to change the restraint centers over time
class colvarbias_restraint_centers_moving
  : public virtual colvarbias_restraint_centers,
    public virtual colvarbias_restraint_moving
{
public:

  colvarbias_restraint_centers_moving(char const *key);
  virtual int init(std::string const &conf);
  virtual int update();

  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);
  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

protected:

  /// \brief New restraint centers
  std::vector<colvarvalue> target_centers;

  /// \brief Amplitude of the restraint centers' increment at each step
  /// (or stage) towards the new values (calculated from target_nsteps)
  std::vector<colvarvalue> centers_incr;

  /// Whether to write the current restraint centers to the trajectory file
  bool b_output_centers;

  /// Whether to write the current accumulated work to the trajectory file
  bool b_output_acc_work;

  /// \brief Accumulated work
  cvm::real acc_work;

  /// Update the accumulated work
  int update_acc_work();
};


/// Options to change the restraint force constant over time
class colvarbias_restraint_k_moving
  : public virtual colvarbias_restraint_k,
    public virtual colvarbias_restraint_moving
{
public:

  colvarbias_restraint_k_moving(char const *key);
  virtual int init(std::string const &conf);
  virtual int update();

  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);
  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

protected:

  /// \brief Restraint force constant (target value)
  cvm::real target_force_k;

  /// \brief Restraint force constant (starting value)
  cvm::real starting_force_k;

  /// \brief Exponent for varying the force constant
  cvm::real force_k_exp;

  /// \brief Intermediate quantity to compute the restraint free energy
  /// (in TI, would be the accumulating FE derivative)
  cvm::real restraint_FE;

  /// \brief Equilibration steps for restraint FE calculation through TI
  cvm::real target_equil_steps;
};


/// \brief Harmonic bias restraint
/// (implementation of \link colvarbias_restraint \endlink)
class colvarbias_restraint_harmonic
  : public colvarbias_restraint_centers_moving,
    public colvarbias_restraint_k_moving
{
public:
  colvarbias_restraint_harmonic(char const *key);
  virtual int init(std::string const &conf);
  virtual int update();
  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);
  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

protected:

  virtual cvm::real restraint_potential(size_t i) const;
  virtual colvarvalue const restraint_force(size_t i) const;
  virtual cvm::real d_restraint_potential_dk(size_t i) const;
};


/// \brief Wall restraint
/// (implementation of \link colvarbias_restraint \endlink)
class colvarbias_restraint_harmonic_walls
  : public colvarbias_restraint_k_moving
{
public:

  colvarbias_restraint_harmonic_walls(char const *key);
  virtual int init(std::string const &conf);
  virtual int update();
  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);
  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

protected:

  /// \brief Location of the lower walls
  std::vector<colvarvalue> lower_walls;

  /// \brief Location of the upper walls
  std::vector<colvarvalue> upper_walls;

  virtual cvm::real colvar_distance(size_t i) const;
  virtual cvm::real restraint_potential(size_t i) const;
  virtual colvarvalue const restraint_force(size_t i) const;
  virtual cvm::real d_restraint_potential_dk(size_t i) const;
};


/// \brief Linear bias restraint
/// (implementation of \link colvarbias_restraint \endlink)
class colvarbias_restraint_linear
  : public colvarbias_restraint_centers_moving,
    public colvarbias_restraint_k_moving
{

public:
  colvarbias_restraint_linear(char const *key);
  virtual int init(std::string const &conf);
  virtual int update();
  virtual std::string const get_state_params() const;
  virtual int set_state_params(std::string const &conf);
  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

protected:

  virtual cvm::real restraint_potential(size_t i) const;
  virtual colvarvalue const restraint_force(size_t i) const;
  virtual cvm::real d_restraint_potential_dk(size_t i) const;
};


/// Restrain the 1D histogram of a set of variables (or of a multidimensional one)
// TODO this could be reimplemented more cleanly as a derived class of both restraint and histogram
class colvarbias_restraint_histogram : public colvarbias {

public:

  colvarbias_restraint_histogram(char const *key);
  int init(std::string const &conf);
  ~colvarbias_restraint_histogram();

  virtual int update();

  virtual std::istream & read_restart(std::istream &is);
  virtual std::ostream & write_restart(std::ostream &os);
  virtual std::ostream & write_traj_label(std::ostream &os);
  virtual std::ostream & write_traj(std::ostream &os);

protected:

  /// Probability density
  cvm::vector1d<cvm::real> p;

  /// Reference probability density
  cvm::vector1d<cvm::real> ref_p;

  /// Difference between probability density and reference
  cvm::vector1d<cvm::real> p_diff;

  /// Lower boundary of the grid
  cvm::real lower_boundary;

  /// Upper boundary of the grid
  cvm::real upper_boundary;

  /// Resolution of the grid
  cvm::real width;

  /// Width of the Gaussians
  cvm::real gaussian_width;

  /// Restraint force constant
  cvm::real force_k;

  /// Write the histogram to a file
  bool b_write_histogram;
};


#endif
