use hmac::{digest::InvalidLength, Hmac, Mac};
use rand::{rngs::StdRng, Error, Rng, SeedableRng};
use sha3::Sha3_256;
use uuid::Uuid;

type Hmac256 = Hmac<Sha3_256>;

enum Flag {
    RngFlag,
    UserSeedFlag,
    UserDerivedFlag,
}

/// Flag
/// - `prefix`: flag prefix with type String
/// - `suffix`: flag suffix with type String
#[allow(dead_code)]
pub struct FlagUnit {
    /// flag prefix with type String
    prefix: String,
    /// flag suffix with type String
    suffix: String,
}
impl FlagUnit {
    /// generates a random suffix flag with given prefix
    ///
    /// example output: "c45f0058099a8a04a8b3dd217081cf25967db333763afaee3719be0ce9c64f99"
    pub fn rng_flag(flag_prefix: String) -> Result<Self, Error> {
        let flag_suffix_result = generate_flag32();

        let flag_suffix = match flag_suffix_result {
            Ok(file) => file,
            Err(error) => return Err(error),
        };
        return Ok(FlagUnit {
            prefix: flag_prefix,
            suffix: flag_suffix,
        });
    }
    /// generates a flag with given prefix
    /// - `flag_prefix`: flag prefix
    ///
    /// and suffix that is based on
    /// - `secret`: secret for generating flags
    /// - `taskid`: taskid for specific task
    /// - `uuid`: user's id
    pub fn user_flag(
        flag_prefix: String,
        secret: String,
        taskid: String,
        uuid: Uuid,
    ) -> Result<Self, InvalidLength> {
        let flag_suffix_result = generate_hmac(uuid, secret, taskid);

        let flag_suffix = match flag_suffix_result {
            Ok(flag) => flag,
            Err(_error) => return Err(InvalidLength),
        };
        return Ok(FlagUnit {
            prefix: flag_prefix,
            suffix: flag_suffix,
        });
    }
    /// returns a flag with given prefix
    /// and suffix seed based on the user
    pub fn user_seed(flag_prefix: String, uuid: Uuid) -> Result<Self, rand::Error> {
        let flag_suffix_result = generate_userseed(uuid);

        let flag_suffix = match flag_suffix_result {
            Ok(flag) => flag,
            Err(error) => return Err(error),
        };
        return Ok(FlagUnit {
            prefix: flag_prefix,
            suffix: flag_suffix,
        });
    }
    /// returns the flag as a single string
    pub fn return_flag(&mut self) -> String {
        let flag_prefix = &self.prefix;
        let flag_suffix = &self.suffix;

        let flag = flag_prefix.to_owned() + ":" + flag_suffix;

        return flag;
    }
}

fn generate_flag32() -> Result<String, Error> {
    let mut rng = StdRng::from_entropy();
    let hex: [u8; 32] = rng.gen();
    let s = hex.iter().map(|b| format!("{:02x}", b)).collect();
    Ok(s)
}

fn generate_hmac(uuid: Uuid, secret: String, taskid: String) -> Result<String, InvalidLength> {
    let input = format!("{}-{}", secret, uuid.as_hyphenated());
    let slice = input.as_bytes();
    let mut mac = Hmac256::new_from_slice(slice)?;
    mac.update(taskid.as_bytes());

    let result = mac.finalize();
    let bytes = result.into_bytes();
    let s = format!("{:x}", bytes);
    return Ok(s);
}
// not used might be used later
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
    return Ok(s == hmac);
}
/// generates a random seed using uuid as a base
fn generate_userseed(uuid: Uuid) -> Result<String, rand::Error> {
    let (_, uuidvalue) = uuid.as_u64_pair();
    let mut rng = StdRng::seed_from_u64(uuidvalue);
    let hex: [u8; 32] = rng.gen();
    let s = hex.iter().map(|b| format!("{:02x}", b)).collect();
    Ok(s)
}

pub fn generate_uuid() -> Result<Uuid, uuid::Error> {
    let id = Uuid::now_v7();
    return Ok(id);
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
        let hash = generate_hmac(id, secret, taskid).expect("error");
        print!("{}", hash);
        assert!(compare_hmac(hash, id, secret2, taskid2).expect("should work"))
    }

    #[test]
    fn test_rand() {
        assert!(generate_flag32().is_ok());
    }
    #[test]
    fn test_userseed() {
        let id1 = Uuid::now_v7();
        let id2 = Uuid::now_v7();
        assert!(generate_userseed(id1).is_ok());

        assert!(
            generate_userseed(id1).expect("no error") != generate_userseed(id2).expect("no error")
        );
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

        let answer1 = generate_flag32().expect("works");
        let answer2 = generate_hmac(id, secret, taskid).expect("works");
        let answer3 = generate_userseed(id).expect("works");

        println!("{}", answer1);
        println!("{}", answer2);
        println!("{}", answer3);

        let mut flag = FlagUnit::user_flag(prefix, secret2, taskid2, id).expect("works");
        let result = flag.return_flag();
        println!("{}", result);
        let mut flag2 = FlagUnit::user_flag(prefix2, secret3, taskid3, id).expect("works");
        let result2 = flag2.return_flag();
        println!("{}", result2);
    }
}
