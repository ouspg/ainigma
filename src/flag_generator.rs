use core::panic;
use hmac::{digest::InvalidLength, Hmac, Mac};
use rand::{rngs::StdRng, Rng, SeedableRng};
use serde::Deserialize;
use sha3::Sha3_256;
use std::fmt::Write;
use uuid::Uuid;

type Hmac256 = Hmac<Sha3_256>;

/// Type for all possible algorithms to use when generating flag
///
///
/// #### Algorithms
/// - `HmacSha3_256` generates a HMAC using SHA3_256 hashing.
#[derive(Debug, PartialEq, Deserialize, Clone)]
#[allow(non_camel_case_types)]
pub enum Algorithm {
    HMAC_SHA3_256,
}

/// Flag type used to generate flag for specific purpose
///
/// Flags are normally 32 long hexstring and all flags need a flag prefix to be used
///
/// #### Flags
/// - `RngFlag` generates a random hexstring flag with given prefix and lenght
/// - `UserSeedFlag` generates a user based seed flag with given prefix, algorithm, secret, taskid and User id (Uuid)
/// - `UserDerivedFlag` generates a user based flag with given prefix, algorithm, secret, taskid and User id (Uuid)
///
/// #### Functions
/// - `random_flag()` - `RngFlag` generator
/// - `user_seed_flag()` - `UserSeedFlag` generator
/// - `user_flag()` - `UserDerivedFlag` generator
/// - `flag_string()` - returns Flag as a one string
#[derive(Debug, Deserialize, Clone)]
pub enum Flag {
    RngFlag(FlagUnit),
    UserSeedFlag(FlagUnit),
    UserDerivedFlag(FlagUnit),
}
impl Flag {
    /// Generates a random hexstring flag with given prefix and lenght
    pub fn new_random_flag(prefix: String, length: u8) -> Self {
        Flag::RngFlag(FlagUnit::rng_flag(prefix, length))
    }
    /// Generates a random hexstring flag with given prefix, algorithm, secret, taskid and Uuid
    pub fn new_user_flag(
        identifier: String,
        algorithm: &Algorithm,
        secret: &str,
        taskid: &str,
        uuid: &Uuid,
    ) -> Self {
        Flag::UserDerivedFlag(FlagUnit::user_flag(
            identifier, algorithm, secret, taskid, uuid,
        ))
    }
    /// Generates a random hexstring flag with given prefix and user id (UUID)
    pub fn new_user_seed_flag(
        identifier: String,
        algorithm: &Algorithm,
        secret: &str,
        taskid: &str,
        uuid: &Uuid,
    ) -> Self {
        Flag::UserSeedFlag(FlagUnit::user_flag(
            identifier, algorithm, secret, taskid, uuid,
        ))
    }
    /// Returns the flag as one string
    pub fn flag_string(&self) -> String {
        match self {
            Flag::RngFlag(rngflag) => rngflag.return_flag(),
            Flag::UserSeedFlag(userseedflag) => userseedflag.return_flag(),
            Flag::UserDerivedFlag(userflag) => userflag.return_flag(),
        }
    }
    pub fn encase_flag(&self) -> String {
        format!("flag{{{}}}", self.flag_string())
    }
    /// Gets the identifier of the flag
    pub fn get_identifier(&self) -> &str {
        match self {
            Flag::RngFlag(rngflag) => rngflag.identifier.as_str(),
            Flag::UserSeedFlag(userseedflag) => userseedflag.identifier.as_str(),
            Flag::UserDerivedFlag(userflag) => userflag.identifier.as_str(),
        }
    }
    /// Returns the flag as a key value pair, typically passed as ENV variable as part of `HashMap`
    pub fn get_flag_type_value_pair(&self) -> (String, String) {
        match self {
            Flag::RngFlag(rngflag) => {
                let flag_key = format!("FLAG_PURE_RANDOM_{}", rngflag.identifier.to_uppercase());
                (flag_key, self.flag_string())
            }
            Flag::UserSeedFlag(userseedflag) => {
                let flag_key = format!("FLAG_USER_SEED_{}", userseedflag.identifier.to_uppercase());
                (flag_key, self.flag_string())
            }
            Flag::UserDerivedFlag(userflag) => {
                let flag_key = format!("FLAG_USER_DERIVED_{}", userflag.identifier.to_uppercase());
                (flag_key, self.flag_string())
            }
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct FlagUnit {
    /// Identifier is typically the same as task id
    identifier: String,
    /// Suffix is the varying part of the flag
    suffix: String,
}
impl FlagUnit {
    fn rng_flag(identifier: String, lenght: u8) -> Self {
        let flag_suffix_result = pure_random_flag(lenght);

        FlagUnit {
            identifier,
            suffix: flag_suffix_result,
        }
    }

    fn user_flag(
        identifier: String,
        algorithm: &Algorithm,
        secret: &str,
        taskid: &str,
        uuid: &Uuid,
    ) -> Self {
        let flag_suffix_result = user_derived_flag(algorithm, uuid, secret, taskid);

        let flag_suffix = match flag_suffix_result {
            Ok(flag) => flag,
            Err(_error) => panic!("Error generating flag"),
        };
        FlagUnit {
            identifier,
            suffix: flag_suffix,
        }
    }

    fn return_flag(&self) -> String {
        format!("{}:{}", self.identifier, self.suffix)
    }
}

fn pure_random_flag(lenght: u8) -> String {
    let mut rng = StdRng::from_entropy();
    let size = lenght.into();
    let mut vec: Vec<u8> = vec![0; size];
    for i in &mut vec {
        *i = rng.gen();
    }
    vec.iter().fold(String::new(), |mut output, b| {
        let _ = write!(output, "{b:02x}");
        output
    })
}

fn user_derived_flag(
    algorithm: &Algorithm,
    uuid: &Uuid,
    secret: &str,
    taskid: &str,
) -> Result<String, InvalidLength> {
    match algorithm {
        Algorithm::HMAC_SHA3_256 => {
            let input = format!("{}-{}", secret, uuid.as_hyphenated());
            let slice = input.as_bytes();
            let mut mac = Hmac256::new_from_slice(slice)?;
            mac.update(taskid.as_bytes());

            let result = mac.finalize();
            let bytes = result.into_bytes();
            Ok(format!("{:x}", bytes))
        }
    }
}
// not used might be used later
#[allow(dead_code)]
fn compare_hmac(
    hmac: String,
    uuid: Uuid,
    secret: String,
    taskid: String,
) -> Result<bool, InvalidLength> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice)?;
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    Ok(s == hmac)
}
/// generates a random seed using uuid as a base

pub fn generate_uuid() -> Result<Uuid, uuid::Error> {
    Ok(Uuid::now_v7())
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn test_compare_hmac() {
        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let taskid = "task1".to_string();
        let secret2 = "Work".to_string();
        let taskid2 = "task1".to_string();
        let hash =
            user_derived_flag(&Algorithm::HMAC_SHA3_256, &id, &secret, &taskid).expect("error");
        print!("{}", hash);
        assert!(compare_hmac(hash, id, secret2, taskid2).expect("should work"))
    }

    #[test]
    fn test_outputs() {
        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let secret2 = "dslpl".to_string();
        let secret3 = "dslpl".to_string();
        let taskid = "task1".to_string();
        let taskid2 = "Wording mording".to_string();
        let taskid3 = "kdosogkdo".to_string();
        let prefix = "task_prefix".to_string();
        let prefix2 = "task_prefix2".to_string();

        let answer1 = pure_random_flag(32);
        let answer2 =
            user_derived_flag(&Algorithm::HMAC_SHA3_256, &id, &secret, &taskid).expect("works");

        println!("{}", answer1);
        println!("{}", answer2);

        let flag = Flag::new_user_flag(prefix, &Algorithm::HMAC_SHA3_256, &secret2, &taskid2, &id);
        let result = flag.flag_string();
        println!("{}", result);
        let flag2 =
            Flag::new_user_flag(prefix2, &Algorithm::HMAC_SHA3_256, &secret3, &taskid3, &id);
        let result2 = flag2.flag_string();
        println!("{}", result2);
    }

    #[test]
    fn test_flags() {
        let id = Uuid::now_v7();
        let prefix = "task1".to_string();
        let prefix2 = "task1".to_string();
        let prefix3 = "task1".to_string();
        let flag = Flag::new_random_flag(prefix, 32);
        let flag2 = Flag::new_user_flag(prefix2, &Algorithm::HMAC_SHA3_256, "This works", "A", &id);
        let flag3 = Flag::new_user_seed_flag(
            prefix3,
            &Algorithm::HMAC_SHA3_256,
            "this also works",
            "B",
            &id,
        );
        let string = flag.flag_string();
        let string2 = flag2.flag_string();
        let string3 = flag3.flag_string();
        println!("{} {} {}", string, string2, string3)
    }
}
