use core::panic;
use hmac::{Hmac, Mac, digest::InvalidLength};
use rand::{Rng, SeedableRng, rngs::StdRng};
use serde::{Deserialize, Serialize};
use sha3::Sha3_256;
use std::fmt::Write;
use uuid::Uuid;

type Hmac256 = Hmac<Sha3_256>;

/// Type for all possible algorithms to use when generating flag
///
///
/// #### Algorithms
/// - `HmacSha3_256` generates a HMAC using SHA3_256 hashing.
#[derive(Debug, PartialEq, Serialize, Deserialize, Clone, Default)]
#[allow(non_camel_case_types)]
#[non_exhaustive]
pub enum Algorithm {
    #[default]
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
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "snake_case")]
pub enum Flag {
    RngFlag(FlagUnit),
    RngSeed(FlagUnit),
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
    /// Generates a random hexstring flag with given prefix and user id (UUID), given as RNG seed for the builders
    pub fn new_rng_seed(
        identifier: String,
        algorithm: &Algorithm,
        secret: &str,
        taskid: &str,
        uuid: &Uuid,
    ) -> Self {
        Flag::RngSeed(FlagUnit::user_flag(
            identifier, algorithm, secret, taskid, uuid,
        ))
    }
    /// Returns the flag as one string
    pub fn flag_string(&self) -> String {
        match self {
            Flag::RngFlag(rngflag) => rngflag.return_flag().trim().to_string(),
            Flag::RngSeed(userseedflag) => userseedflag.return_flag().trim().to_string(),
            Flag::UserDerivedFlag(userflag) => userflag.return_flag().trim().to_string(),
        }
    }
    pub fn encased(&self) -> &str {
        match self {
            Flag::RngFlag(rngflag) => &rngflag.encased,
            Flag::RngSeed(userseedflag) => &userseedflag.encased,
            Flag::UserDerivedFlag(userflag) => &userflag.encased,
        }
    }
    /// Gets the identifier of the flag
    pub fn get_identifier(&self) -> &str {
        match self {
            Flag::RngFlag(rngflag) => rngflag.identifier.as_str(),
            Flag::RngSeed(userseedflag) => userseedflag.identifier.as_str(),
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
            Flag::RngSeed(userseedflag) => {
                let flag_key = format!("FLAG_RNG_SEED_{}", userseedflag.identifier.to_uppercase());
                (flag_key, self.flag_string())
            }
            Flag::UserDerivedFlag(userflag) => {
                let flag_key = format!("FLAG_USER_DERIVED_{}", userflag.identifier.to_uppercase());
                (flag_key, self.flag_string())
            }
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FlagUnit {
    /// Identifier is typically the same as task id
    identifier: String,
    /// Suffix is the varying part of the flag
    suffix: String,
    /// Encased flag is the flag in the format of `flag{identifier:suffix}`
    encased: String,
}
impl FlagUnit {
    fn rng_flag(identifier: String, lenght: u8) -> Self {
        let suffix = pure_random_flag(lenght);

        let encased = format!("flag{{{identifier}:{suffix}}}");
        FlagUnit {
            identifier,
            suffix,
            encased,
        }
    }
    pub fn value(&self) -> &str {
        self.suffix.as_str()
    }
    pub fn update_suffix(&mut self, new_suffix: String) {
        self.suffix = new_suffix;
    }

    fn user_flag(
        identifier: String,
        algorithm: &Algorithm,
        secret: &str,
        taskid: &str,
        uuid: &Uuid,
    ) -> Self {
        let suffix = user_derived_flag(algorithm, uuid, secret, taskid);
        let flag_suffix = match suffix {
            Ok(flag) => flag,
            Err(_error) => panic!("Error generating flag"),
        };
        let encased = format!("flag{{{identifier}:{flag_suffix}}}");

        FlagUnit {
            identifier,
            suffix: flag_suffix,
            encased,
        }
    }

    fn return_flag(&self) -> String {
        format!("{}:{}", self.identifier, self.suffix)
    }
}

/// Generates a completely random flag
fn pure_random_flag(lenght: u8) -> String {
    let mut rng = StdRng::from_os_rng();
    let size = lenght.into();
    let mut vec: Vec<u8> = vec![0; size];
    for i in &mut vec {
        *i = rng.random();
    }
    vec.iter().fold(String::new(), |mut output, b| {
        let _ = write!(output, "{b:02x}");
        output
    })
}

/// Generates a flag which is derived from user identifier and uses secret
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
            Ok(format!("{bytes:x}"))
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
    let s = format!("{bytes:x}");
    Ok(s == hmac)
}

/// Generates a UUID version 7
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
        print!("{hash}");
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

        println!("{answer1}");
        println!("{answer2}");

        let flag = Flag::new_user_flag(prefix, &Algorithm::HMAC_SHA3_256, &secret2, &taskid2, &id);
        let result = flag.flag_string();
        println!("{result}");
        let flag2 =
            Flag::new_user_flag(prefix2, &Algorithm::HMAC_SHA3_256, &secret3, &taskid3, &id);
        let result2 = flag2.flag_string();
        println!("{result2}");
    }

    #[test]
    fn test_flags() {
        let id = Uuid::now_v7();
        let prefix = "task1".to_string();
        let prefix2 = "task1".to_string();
        let prefix3 = "task1".to_string();
        let flag = Flag::new_random_flag(prefix, 32);
        let flag2 = Flag::new_user_flag(prefix2, &Algorithm::HMAC_SHA3_256, "This works", "A", &id);
        let flag3 = Flag::new_rng_seed(
            prefix3,
            &Algorithm::HMAC_SHA3_256,
            "this also works",
            "B",
            &id,
        );
        let string = flag.flag_string();
        let string2 = flag2.flag_string();
        let string3 = flag3.flag_string();
        println!("{string} {string2} {string3}")
    }
}
